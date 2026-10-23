<?php

namespace App\Services;

use App\Events\PrivateSignal;
use App\Exceptions\RpcError;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class ModerationOperations
{
    public function __construct(
        private readonly AccountService $accounts,
        private readonly WallOperations $wall,
        private readonly NotificationService $notifications,
    ) {}

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getModerationQueue(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $limit = $this->limit($params['p_limit'] ?? 50);
        $rows = DB::table('moderation_queue as q')
            ->leftJoin('notes as n', function ($join): void {
                $join->on('q.target_id', '=', 'n.id')->where('q.target_type', '=', 'note');
            })
            ->leftJoin('messages as m', function ($join): void {
                $join->on('q.target_id', '=', 'm.id')->where('q.target_type', '=', 'message');
            })
            ->whereIn('q.queue_status', ['pending', 'reviewing'])
            ->orderBy('q.created_at')->orderBy('q.id')->limit($limit)
            ->get([
                'q.id', 'q.target_type', 'q.target_id', 'q.reason_code', 'q.queue_status', 'q.created_at',
                'n.content as note_content', 'n.paper_color', 'n.status as note_status',
                'm.body as message_content', 'm.status as message_status',
            ]);
        $items = $rows->map(function (object $row): array {
            $isNote = $row->target_type === 'note';

            return [
                'id' => (string) $row->id,
                'target_type' => $row->target_type,
                'target_id' => (string) $row->target_id,
                'reason_code' => $row->reason_code,
                'status' => $row->queue_status,
                'content' => $isNote ? ($row->note_content ?? '') : ($row->message_content ?? ''),
                'paper_color' => $isNote ? $row->paper_color : null,
                'content_status' => $isNote ? $row->note_status : $row->message_status,
                'created_at' => $row->created_at,
            ];
        })->all();

        return ['items' => $items];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getReportsQueue(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $limit = $this->limit($params['p_limit'] ?? 50);
        $reports = DB::table('reports')->whereIn('status', ['pending', 'reviewing'])
            ->orderBy('created_at')->orderBy('id')->limit($limit)->get();
        $items = $reports->map(function (object $report): array {
            $content = match ($report->target_type) {
                'note' => DB::table('notes')->where('id', $report->target_id)->value('content'),
                'message' => DB::table('messages')->where('id', $report->target_id)->value('body'),
                default => null,
            };

            return [
                'report_id' => (string) $report->id,
                'target_type' => $report->target_type,
                'target_id' => $report->target_type === 'user' ? null : (string) $report->target_id,
                'reason' => $report->reason,
                'description' => $report->description,
                'status' => $report->status,
                'created_at' => $report->created_at,
                'content' => $content,
            ];
        })->all();

        return ['items' => $items];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getDeletionQueue(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $items = DB::table('account_deletion_requests')
            ->whereIn('status', ['pending', 'processing', 'held'])
            ->orderBy('requested_at')->orderBy('id')->limit($this->limit($params['p_limit'] ?? 50))
            ->get(['id', 'status', 'requested_at', 'resolution_code'])
            ->map(fn (object $request): array => [
                'request_id' => (string) $request->id,
                'status' => $request->status,
                'requested_at' => $request->requested_at,
                'resolution_code' => $request->resolution_code,
            ])->all();

        return ['items' => $items];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function moderateNote(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $action = $this->requiredAction($params, 'p_action', ['publish', 'hide', 'reject', 'delete', 'restore']);
        $reason = $this->reason($params);

        return DB::transaction(function () use ($actorId, $noteId, $action, $reason): array {
            $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
            if ($note === null) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            $nextStatus = match ($action) {
                'publish', 'restore' => 'published',
                'hide' => 'hidden',
                'reject' => 'rejected',
                'delete' => 'deleted',
            };
            if ($note->status === 'deleted'
                || $action === 'publish' && $note->status !== 'pending_review'
                || $action === 'reject' && $note->status !== 'pending_review'
                || $action === 'hide' && $note->status !== 'published'
                || $action === 'restore' && $note->status !== 'hidden') {
                throw new RpcError('INVALID_STATE', '', false, 409);
            }

            $now = now();
            DB::table('notes')->where('id', $noteId)->update([
                'status' => $nextStatus,
                'published_at' => $nextStatus === 'published' ? ($note->published_at ?? $now) : $note->published_at,
                'deleted_at' => $nextStatus === 'deleted' ? ($note->deleted_at ?? $now) : $note->deleted_at,
                'content' => $nextStatus === 'deleted' ? '' : $note->content,
                'allow_chat' => in_array($nextStatus, ['deleted', 'rejected'], true) ? false : $note->allow_chat,
                'updated_at' => $now,
            ]);
            if (in_array($nextStatus, ['deleted', 'rejected'], true)) {
                DB::table('active_note_cells')->where('note_id', $noteId)->delete();
            }
            $this->resolveQueue('note', $noteId);
            $this->recordNoteEvent($noteId, $actorId, $note->status, $nextStatus, $reason);
            $this->audit($actorId, 'moderate_note:'.$action, 'note', $noteId, $reason);

            if (($note->status === 'published') !== ($nextStatus === 'published')) {
                $this->wall->syncPublishedRegion((int) $note->cell_x, (int) $note->cell_y);
            }

            return ['status' => $nextStatus];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function moderateMessage(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $messageId = $this->uuid($params, 'p_message_id');
        $action = $this->requiredAction($params, 'p_action', ['approve', 'reject', 'hide']);
        $reason = $this->reason($params);

        return DB::transaction(function () use ($actorId, $messageId, $action, $reason): array {
            $message = DB::table('messages')->where('id', $messageId)->lockForUpdate()->first();
            if ($message === null) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            $conversation = DB::table('conversations')->where('id', $message->conversation_id)->lockForUpdate()->first();
            if ($conversation === null) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }

            if ($action === 'approve') {
                if ($message->status !== 'pending_review' || $conversation->status !== 'active') {
                    throw new RpcError('INVALID_STATE', '', false, 409);
                }
                $recipientId = $message->sender_id === $conversation->participant_low
                    ? (string) $conversation->participant_high
                    : (string) $conversation->participant_low;
                if ($this->isBlockedBetween((string) $message->sender_id, $recipientId)) {
                    throw new RpcError('BLOCKED', '', false, 403);
                }
                DB::table('messages')->where('id', $messageId)->update(['status' => 'delivered']);
                $this->notifications->create($recipientId, 'message', $messageId, (string) $message->conversation_id);
                $this->resolveQueue('message', $messageId);
                PrivateSignal::dispatch('conversation:'.$message->conversation_id, 'conversation_updated');
                PrivateSignal::dispatch('user:'.$recipientId, 'inbox_updated');
                $nextStatus = 'delivered';
            } elseif ($action === 'reject') {
                if ($message->status !== 'pending_review') {
                    throw new RpcError('INVALID_STATE', '', false, 409);
                }
                DB::table('messages')->where('id', $messageId)->update(['status' => 'rejected']);
                $this->resolveQueue('message', $messageId);
                $nextStatus = 'rejected';
            } else {
                if ($message->status !== 'delivered') {
                    throw new RpcError('INVALID_STATE', '', false, 409);
                }
                DB::table('messages')->where('id', $messageId)->update(['status' => 'hidden']);
                DB::table('notifications')->where('notification_type', 'message')->where('source_id', $messageId)->delete();
                $this->resolveQueue('message', $messageId);
                PrivateSignal::dispatch('conversation:'.$message->conversation_id, 'message_hidden');
                PrivateSignal::dispatch('user:'.$conversation->participant_low, 'inbox_updated');
                PrivateSignal::dispatch('user:'.$conversation->participant_high, 'inbox_updated');
                $nextStatus = 'hidden';
            }

            DB::table('message_moderation_events')->insert([
                'id' => (string) Str::uuid(),
                'message_id' => $messageId,
                'actor_id' => $actorId,
                'reason_code' => mb_substr($reason, 0, 100),
                'created_at' => now(),
            ]);
            $this->audit($actorId, 'moderate_message:'.$action, 'message', $messageId, $reason);

            return ['status' => $nextStatus];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reviewReport(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $reportId = $this->uuid($params, 'p_report_id');
        $action = $this->requiredAction($params, 'p_action', ['start_review', 'resolve', 'dismiss', 'hide_content', 'suspend_user']);
        $reason = $this->reason($params);

        return DB::transaction(function () use ($actorId, $reportId, $action, $reason): array {
            $report = DB::table('reports')->where('id', $reportId)->lockForUpdate()->first();
            if ($report === null) {
                throw new RpcError('REPORT_NOT_FOUND', '', false, 404);
            }
            if (in_array($report->status, ['resolved', 'dismissed'], true)) {
                throw new RpcError('INVALID_STATE', '', false, 409);
            }
            if ($action === 'suspend_user' && $report->target_type !== 'user') {
                throw new RpcError('INVALID_INPUT');
            }
            if ($report->target_type === 'user' && in_array($action, ['hide_content', 'suspend_user'], true)
                && $report->target_id === $actorId) {
                throw new RpcError('INVALID_INPUT');
            }

            if (in_array($action, ['hide_content', 'suspend_user'], true)) {
                $this->applyReportAction($actorId, $report, $reason);
                $nextStatus = 'resolved';
            } else {
                $nextStatus = match ($action) {
                    'start_review' => 'reviewing',
                    'resolve' => 'resolved',
                    'dismiss' => 'dismissed',
                };
            }

            $resolvedAt = in_array($nextStatus, ['resolved', 'dismissed'], true) ? now() : null;
            DB::table('reports')->where('id', $reportId)->update([
                'status' => $nextStatus,
                'moderator_id' => $actorId,
                'resolved_at' => $resolvedAt,
                'updated_at' => now(),
            ]);
            $this->audit($actorId, 'review_report:'.$action, 'report', $reportId, $reason);

            return ['status' => $nextStatus];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function processDeletionRequest(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $requestId = $this->uuid($params, 'p_request_id');
        $action = $this->requiredAction($params, 'p_action', ['start_processing', 'hold']);
        $reason = $this->reason($params);

        return DB::transaction(function () use ($actorId, $requestId, $action, $reason): array {
            $request = DB::table('account_deletion_requests')->where('id', $requestId)->lockForUpdate()->first();
            if ($request === null) {
                throw new RpcError('DELETION_REQUEST_NOT_FOUND', '', false, 404);
            }
            if ($request->status === 'completed' || ($request->status === 'held' && $action === 'start_processing')) {
                throw new RpcError('INVALID_STATE', '', false, 409);
            }
            $nextStatus = $action === 'start_processing' ? 'processing' : 'held';
            DB::table('account_deletion_requests')->where('id', $requestId)->update([
                'status' => $nextStatus,
                'resolution_code' => mb_substr($reason, 0, 100),
                'updated_at' => now(),
            ]);
            $this->audit($actorId, 'process_deletion_request:'.$action, 'deletion_request', $requestId, $reason);

            return ['status' => $nextStatus];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function moderateAccount(string $actorId, array $params): array
    {
        $this->requireModerator($actorId);
        $targetId = $this->uuid($params, 'p_target_user_id');
        $action = $this->requiredAction($params, 'p_action', ['suspend', 'restore']);
        $reason = $this->reason($params);
        if ($targetId === $actorId) {
            throw new RpcError('INVALID_INPUT');
        }

        return DB::transaction(function () use ($actorId, $targetId, $action, $reason): array {
            $profile = DB::table('profiles')->where('user_id', $targetId)->lockForUpdate()->first();
            if ($profile === null) {
                throw new RpcError('ACCOUNT_NOT_FOUND', '', false, 404);
            }
            $nextStatus = $action === 'suspend' ? 'suspended' : 'active';
            DB::table('profiles')->where('user_id', $targetId)->update([
                'account_status' => $nextStatus,
                'updated_at' => now(),
            ]);
            if ($action === 'suspend') {
                $this->suspendUserContent($actorId, $targetId, $reason);
            }
            $this->audit($actorId, 'moderate_account:'.$action, 'user', $targetId, $reason);

            return ['account_status' => $nextStatus];
        }, 3);
    }

    private function applyReportAction(string $actorId, object $report, string $reason): void
    {
        if ($report->target_type === 'note') {
            $note = DB::table('notes')->where('id', $report->target_id)->lockForUpdate()->first();
            if ($note === null) {
                throw new RpcError('REPORT_TARGET_NOT_FOUND', '', false, 404);
            }
            if ($note->status === 'published') {
                DB::table('notes')->where('id', $note->id)->update(['status' => 'hidden', 'updated_at' => now()]);
                $this->recordNoteEvent((string) $note->id, $actorId, $note->status, 'hidden', $reason);
                $this->wall->syncPublishedRegion((int) $note->cell_x, (int) $note->cell_y);
            } elseif (! in_array($note->status, ['hidden', 'rejected', 'deleted'], true)) {
                throw new RpcError('INVALID_STATE', '', false, 409);
            }

            return;
        }

        if ($report->target_type === 'message') {
            $message = DB::table('messages')->where('id', $report->target_id)->lockForUpdate()->first();
            if ($message === null) {
                throw new RpcError('REPORT_TARGET_NOT_FOUND', '', false, 404);
            }
            if (in_array($message->status, ['delivered', 'pending_review'], true)) {
                DB::table('messages')->where('id', $message->id)->update(['status' => 'hidden']);
                $this->recordMessageEvent((string) $message->id, $actorId, $reason);
                $this->resolveQueue('message', (string) $message->id);
                DB::table('notifications')->where('notification_type', 'message')->where('source_id', $message->id)->delete();
                $this->signalConversationParticipants((string) $message->conversation_id, 'message_hidden');
            } elseif ($message->status !== 'hidden') {
                throw new RpcError('INVALID_STATE', '', false, 409);
            }

            return;
        }

        if ($report->target_type === 'conversation') {
            $conversation = DB::table('conversations')->where('id', $report->target_id)->lockForUpdate()->first();
            if ($conversation === null) {
                throw new RpcError('REPORT_TARGET_NOT_FOUND', '', false, 404);
            }
            DB::table('conversations')->where('id', $conversation->id)->where('status', 'active')->update([
                'status' => 'suspended',
                'updated_at' => now(),
            ]);
            $messages = DB::table('messages')->where('conversation_id', $conversation->id)
                ->whereIn('status', ['delivered', 'pending_review'])->get(['id']);
            DB::table('messages')->whereIn('id', $messages->pluck('id')->all())->update(['status' => 'hidden']);
            foreach ($messages as $message) {
                $this->resolveQueue('message', (string) $message->id);
            }
            DB::table('notifications')->where('conversation_id', $conversation->id)->delete();
            $this->signalConversationParticipants((string) $conversation->id, 'conversation_closed');

            return;
        }

        $profile = DB::table('profiles')->where('user_id', $report->target_id)->lockForUpdate()->first();
        if ($profile === null) {
            throw new RpcError('REPORT_TARGET_NOT_FOUND', '', false, 404);
        }
        if ($profile->account_status === 'active') {
            DB::table('profiles')->where('user_id', $report->target_id)->update([
                'account_status' => 'suspended',
                'updated_at' => now(),
            ]);
        } elseif ($profile->account_status !== 'suspended') {
            throw new RpcError('REPORT_TARGET_NOT_FOUND', '', false, 404);
        }
        $this->suspendUserContent($actorId, (string) $report->target_id, $reason, true);
    }

    private function suspendUserContent(string $actorId, string $targetId, string $reason, bool $writeAccountAudit = false): void
    {
        $notes = DB::table('notes')->where('author_id', $targetId)->where('status', 'published')
            ->get(['id', 'cell_x', 'cell_y', 'status']);
        DB::table('notes')->whereIn('id', $notes->pluck('id')->all())->update([
            'status' => 'hidden',
            'updated_at' => now(),
        ]);
        foreach ($notes as $note) {
            $this->recordNoteEvent((string) $note->id, $actorId, 'published', 'hidden', $reason);
            $this->wall->syncPublishedRegion((int) $note->cell_x, (int) $note->cell_y);
        }

        $conversations = DB::table('conversations')->where('status', 'active')->where(function ($participants) use ($targetId): void {
            $participants->where('participant_low', $targetId)->orWhere('participant_high', $targetId);
        })->get(['id']);
        $conversationIds = $conversations->pluck('id')->all();
        DB::table('conversations')->whereIn('id', $conversationIds)->update([
            'status' => 'suspended',
            'updated_at' => now(),
        ]);
        DB::table('notifications')->where('recipient_id', $targetId)
            ->orWhereIn('conversation_id', $conversationIds)->delete();
        DB::table('user_devices')->where('user_id', $targetId)->delete();
        foreach ($conversationIds as $conversationId) {
            $this->signalConversationParticipants((string) $conversationId, 'conversation_closed');
        }
        if ($writeAccountAudit) {
            $this->audit($actorId, 'suspend_account_from_report', 'user', $targetId, $reason);
        }
    }

    private function signalConversationParticipants(string $conversationId, string $eventType): void
    {
        $conversation = DB::table('conversations')->where('id', $conversationId)
            ->first(['participant_low', 'participant_high']);
        if ($conversation === null) {
            return;
        }
        PrivateSignal::dispatch('conversation:'.$conversationId, $eventType);
        PrivateSignal::dispatch('user:'.$conversation->participant_low, 'inbox_updated');
        PrivateSignal::dispatch('user:'.$conversation->participant_high, 'inbox_updated');
    }

    private function recordNoteEvent(string $noteId, ?string $actorId, ?string $fromStatus, string $toStatus, string $reason): void
    {
        DB::table('moderation_events')->insert([
            'id' => (string) Str::uuid(),
            'note_id' => $noteId,
            'actor_id' => $actorId,
            'from_status' => $fromStatus,
            'to_status' => $toStatus,
            'reason_code' => mb_substr($reason, 0, 100),
            'created_at' => now(),
        ]);
    }

    private function recordMessageEvent(string $messageId, ?string $actorId, string $reason): void
    {
        DB::table('message_moderation_events')->insert([
            'id' => (string) Str::uuid(),
            'message_id' => $messageId,
            'actor_id' => $actorId,
            'reason_code' => mb_substr($reason, 0, 100),
            'created_at' => now(),
        ]);
    }

    private function resolveQueue(string $type, string $targetId): void
    {
        DB::table('moderation_queue')->where('target_type', $type)->where('target_id', $targetId)
            ->whereIn('queue_status', ['pending', 'reviewing'])
            ->update(['queue_status' => 'resolved', 'updated_at' => now()]);
    }

    private function audit(string $actorId, string $action, string $targetType, ?string $targetId, string $reason): void
    {
        DB::table('admin_audit_logs')->insert([
            'id' => (string) Str::uuid(),
            'actor_id' => $actorId,
            'action' => $action,
            'target_type' => $targetType,
            'target_id' => $targetId,
            'reason' => mb_substr($reason, 0, 500),
            'created_at' => now(),
        ]);
    }

    private function isBlockedBetween(string $firstUserId, string $secondUserId): bool
    {
        return DB::table('blocks')->where(function ($query) use ($firstUserId, $secondUserId): void {
            $query->where(function ($pair) use ($firstUserId, $secondUserId): void {
                $pair->where('blocker_id', $firstUserId)->where('blocked_id', $secondUserId);
            })->orWhere(function ($pair) use ($firstUserId, $secondUserId): void {
                $pair->where('blocker_id', $secondUserId)->where('blocked_id', $firstUserId);
            });
        })->exists();
    }

    private function requireModerator(string $actorId): void
    {
        if (! $this->accounts->isModerator($actorId)) {
            throw new RpcError('NOT_AUTHORIZED', '', false, 403);
        }
    }

    private function limit(mixed $value): int
    {
        if (! is_int($value) && ! (is_string($value) && ctype_digit($value))) {
            throw new RpcError('INVALID_INPUT');
        }

        return max(1, min(100, (int) $value));
    }

    /** @param array<string, mixed> $params
     * @param  list<string>  $allowed
     */
    private function requiredAction(array $params, string $key, array $allowed): string
    {
        $value = $params[$key] ?? null;
        if (! is_string($value) || ! in_array($value, $allowed, true)) {
            throw new RpcError('INVALID_INPUT');
        }

        return $value;
    }

    /** @param array<string, mixed> $params */
    private function reason(array $params): string
    {
        $value = $params['p_reason'] ?? null;
        if (! is_string($value)) {
            throw new RpcError('INVALID_INPUT');
        }
        $reason = trim($value);
        if ($reason === '' || mb_strlen($reason) > 500) {
            throw new RpcError('INVALID_INPUT');
        }

        return $reason;
    }

    /** @param array<string, mixed> $params */
    private function uuid(array $params, string $key): string
    {
        $value = $params[$key] ?? null;
        if (! is_string($value) || ! Str::isUuid($value)) {
            throw new RpcError('INVALID_INPUT');
        }

        return $value;
    }
}
