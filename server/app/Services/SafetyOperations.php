<?php

namespace App\Services;

use App\Events\PrivateSignal;
use App\Exceptions\RpcError;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class SafetyOperations
{
    private const REPORT_REASONS = [
        'harassment',
        'hate',
        'sexual_content',
        'self_harm_concern',
        'personal_info',
        'spam',
        'other',
    ];

    public function __construct(
        private readonly AccountService $accounts,
        private readonly WallOperations $wall,
    ) {}

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function markNotificationRead(string $actorId, array $params): array
    {
        $notificationId = $this->uuid($params, 'p_notification_id');

        DB::table('notifications')->where('id', $notificationId)
            ->where('recipient_id', $actorId)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return ['read' => true];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function blockFromNote(string $actorId, array $params): array
    {
        $noteId = $this->uuid($params, 'p_note_id');

        DB::transaction(function () use ($actorId, $noteId): void {
            $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
            if ($note === null || ! in_array($note->status, ['published', 'hidden'], true)) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            if ($note->author_id === $actorId) {
                throw new RpcError('INVALID_INPUT');
            }

            $this->createBlock($actorId, (string) $note->author_id, $noteId);
        }, 3);

        return ['blocked' => true];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function blockFromConversation(string $actorId, array $params): array
    {
        $conversationId = $this->uuid($params, 'p_conversation_id');

        DB::transaction(function () use ($actorId, $conversationId): void {
            $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
            if ($conversation === null || ! $this->isParticipant($conversation, $actorId)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }

            $targetId = $conversation->participant_low === $actorId
                ? (string) $conversation->participant_high
                : (string) $conversation->participant_low;

            $this->createBlock($actorId, $targetId, null);
        }, 3);

        return ['blocked' => true];
    }

    /** @return array<string, mixed> */
    public function getMyBlocks(string $actorId): array
    {
        $items = DB::table('blocks')->where('blocker_id', $actorId)
            ->orderByDesc('created_at')->orderByDesc('id')
            ->get(['id', 'created_at'])
            ->map(fn (object $block): array => [
                'block_ref' => (string) $block->id,
                'created_at' => $block->created_at,
            ])->all();

        return ['items' => $items];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function unblockFromMyList(string $actorId, array $params): array
    {
        $blockId = $this->uuid($params, 'p_block_ref');
        $deleted = DB::table('blocks')->where('id', $blockId)->where('blocker_id', $actorId)->delete();

        return ['unblocked' => $deleted > 0];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportContent(string $actorId, array $params): array
    {
        $targetType = $params['p_target_type'] ?? null;
        if (! is_string($targetType) || $targetType === 'user') {
            throw new RpcError('INVALID_INPUT');
        }
        $targetId = $this->uuid($params, 'p_target_id');

        return DB::transaction(fn (): array => $this->createReport(
            $actorId,
            $targetType,
            $targetId,
            $params['p_reason'] ?? null,
            $params['p_description'] ?? null,
        ), 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportUserFromNote(string $actorId, array $params): array
    {
        $noteId = $this->uuid($params, 'p_note_id');

        return DB::transaction(function () use ($actorId, $noteId, $params): array {
            $note = DB::table('notes')->where('id', $noteId)->where('status', 'published')->lockForUpdate()->first();
            if ($note === null || $note->author_id === $actorId) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }

            return $this->createReport(
                $actorId,
                'user',
                (string) $note->author_id,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportUserFromConversation(string $actorId, array $params): array
    {
        $conversationId = $this->uuid($params, 'p_conversation_id');

        return DB::transaction(function () use ($actorId, $conversationId, $params): array {
            $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
            if ($conversation === null || ! $this->isParticipant($conversation, $actorId)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }
            $targetId = $conversation->participant_low === $actorId
                ? (string) $conversation->participant_high
                : (string) $conversation->participant_low;

            return $this->createReport(
                $actorId,
                'user',
                $targetId,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportAndBlockUserFromNote(string $actorId, array $params): array
    {
        return $this->reportAndBlockFromNote($actorId, $params, true);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportAndBlockUserFromConversation(string $actorId, array $params): array
    {
        return $this->reportAndBlockFromConversation($actorId, $params, true);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportAndBlockNote(string $actorId, array $params): array
    {
        $noteId = $this->uuid($params, 'p_note_id');

        return DB::transaction(function () use ($actorId, $noteId, $params): array {
            $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
            if ($note === null || ! in_array($note->status, ['published', 'hidden'], true) || $note->author_id === $actorId) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }

            $report = $this->createReport(
                $actorId,
                'note',
                $noteId,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
            $this->createBlock($actorId, (string) $note->author_id, $noteId);

            return ['report_id' => $report['report_id'], 'blocked' => true];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportAndBlockConversation(string $actorId, array $params): array
    {
        $conversationId = $this->uuid($params, 'p_conversation_id');

        return DB::transaction(function () use ($actorId, $conversationId, $params): array {
            $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
            if ($conversation === null || ! $this->isParticipant($conversation, $actorId)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }
            $targetId = $conversation->participant_low === $actorId
                ? (string) $conversation->participant_high
                : (string) $conversation->participant_low;
            $report = $this->createReport(
                $actorId,
                'conversation',
                $conversationId,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
            $this->createBlock($actorId, $targetId, null);

            return ['report_id' => $report['report_id'], 'blocked' => true];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function reportAndBlockMessage(string $actorId, array $params): array
    {
        $messageId = $this->uuid($params, 'p_message_id');

        return DB::transaction(function () use ($actorId, $messageId, $params): array {
            $message = DB::table('messages as m')
                ->join('conversations as c', 'c.id', '=', 'm.conversation_id')
                ->where('m.id', $messageId)
                ->where(function ($participants) use ($actorId): void {
                    $participants->where('c.participant_low', $actorId)->orWhere('c.participant_high', $actorId);
                })
                ->lockForUpdate()
                ->first(['m.id', 'm.conversation_id', 'm.sender_id']);
            if ($message === null || $message->sender_id === $actorId) {
                throw new RpcError('MESSAGE_NOT_FOUND', '', false, 404);
            }
            $conversation = DB::table('conversations')->where('id', $message->conversation_id)->lockForUpdate()->first();
            if ($conversation === null || ! $this->isParticipant($conversation, $actorId)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }
            $report = $this->createReport(
                $actorId,
                'message',
                $messageId,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
            $targetId = $conversation->participant_low === $actorId
                ? (string) $conversation->participant_high
                : (string) $conversation->participant_low;
            $this->createBlock($actorId, $targetId, null);

            return ['report_id' => $report['report_id'], 'blocked' => true];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function requestAccountDeletion(string $actorId, array $params): array
    {
        $requestId = $this->uuid($params, 'p_client_request_id');
        if (($params['p_confirm'] ?? null) !== true) {
            throw new RpcError('INVALID_INPUT');
        }

        return DB::transaction(function () use ($actorId, $requestId): array {
            DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
            $payloadHash = hash('sha256', 'request_account_deletion');
            $previous = DB::table('request_idempotency')
                ->where('actor_id', $actorId)
                ->where('operation', 'request_account_deletion')
                ->where('request_id', $requestId)
                ->first();
            if ($previous !== null) {
                if (! hash_equals($previous->payload_hash, $payloadHash)) {
                    throw new RpcError('IDEMPOTENCY_CONFLICT', '', false, 409);
                }
                $decoded = json_decode($previous->result, true);
                if (is_array($decoded) && isset($decoded['data']) && is_array($decoded['data'])) {
                    return $decoded['data'];
                }
                throw new RpcError('SERVICE_UNAVAILABLE', '', true, 503);
            }

            $profile = DB::table('profiles')->where('user_id', $actorId)->lockForUpdate()->first();
            if ($profile === null || $profile->account_status === 'deleted') {
                throw new RpcError('ACCOUNT_NOT_FOUND', '', false, 404);
            }
            DB::table('profiles')->where('user_id', $actorId)->update([
                'account_status' => 'deletion_requested',
                'updated_at' => now(),
            ]);

            $notes = DB::table('notes')->where('author_id', $actorId)
                ->whereIn('status', ['pending_review', 'published', 'hidden'])
                ->get(['id', 'cell_x', 'cell_y', 'status']);
            DB::table('notes')->whereIn('id', $notes->pluck('id')->all())->update([
                'status' => 'deleted',
                'deleted_at' => now(),
                'content' => '',
                'allow_chat' => false,
                'updated_at' => now(),
            ]);
            DB::table('active_note_cells')->whereIn('note_id', $notes->pluck('id')->all())->delete();
            DB::table('moderation_queue')->where('target_type', 'note')
                ->whereIn('target_id', $notes->pluck('id')->all())
                ->update(['queue_status' => 'resolved', 'updated_at' => now()]);
            $regions = [];
            foreach ($notes as $note) {
                if ($note->status === 'published') {
                    $tileX = (int) floor((int) $note->cell_x / 8);
                    $tileY = (int) floor((int) $note->cell_y / 8);
                    $regions[$tileX.':'.$tileY] = [(int) $note->cell_x, (int) $note->cell_y];
                }
            }
            foreach ($regions as [$cellX, $cellY]) {
                $this->wall->syncPublishedRegion($cellX, $cellY);
            }

            $conversations = DB::table('conversations')->where(function ($participants) use ($actorId): void {
                $participants->where('participant_low', $actorId)->orWhere('participant_high', $actorId);
            })->where('status', '<>', 'suspended')->lockForUpdate()->get(['id', 'participant_low', 'participant_high', 'status']);
            foreach ($conversations as $conversation) {
                $nextStatus = $conversation->status === 'blocked' ? 'blocked' : 'closed_by_user';
                DB::table('conversations')->where('id', $conversation->id)->update([
                    'status' => $nextStatus,
                    'updated_at' => now(),
                ]);
                if ($nextStatus === 'closed_by_user') {
                    PrivateSignal::dispatch('user:'.$conversation->participant_low, 'inbox_updated');
                    PrivateSignal::dispatch('user:'.$conversation->participant_high, 'inbox_updated');
                }
            }

            DB::table('notifications')->where('recipient_id', $actorId)->delete();
            DB::table('user_devices')->where('user_id', $actorId)->delete();
            DB::table('personal_access_tokens')
                ->where('tokenable_type', User::class)
                ->where('tokenable_id', $actorId)
                ->delete();

            $existingRequest = DB::table('account_deletion_requests')->where('user_id', $actorId)->first();
            if ($existingRequest === null) {
                $deletionRequestId = (string) Str::uuid();
                DB::table('account_deletion_requests')->insert([
                    'id' => $deletionRequestId,
                    'user_id' => $actorId,
                    'status' => 'pending',
                    'requested_at' => now(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                $existingRequest = DB::table('account_deletion_requests')->where('id', $deletionRequestId)->first();
            } else {
                DB::table('account_deletion_requests')->where('id', $existingRequest->id)->update(['updated_at' => now()]);
                $existingRequest = DB::table('account_deletion_requests')->where('id', $existingRequest->id)->first();
            }

            $payload = [
                'request_id' => (string) $existingRequest->id,
                'status' => $existingRequest->status,
                'requested_at' => $existingRequest->requested_at,
                'account_access_disabled' => true,
            ];
            DB::table('request_idempotency')->insert([
                'actor_id' => $actorId,
                'operation' => 'request_account_deletion',
                'request_id' => $requestId,
                'payload_hash' => $payloadHash,
                'result' => json_encode(['data' => $payload], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
                'created_at' => now(),
                'expires_at' => now()->addDays(30),
            ]);

            return $payload;
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function registerDevice(string $actorId, array $params): array
    {
        if (! $this->accounts->isEligible($actorId)) {
            throw new RpcError('NOT_ELIGIBLE', '', false, 403);
        }
        if (! DB::table('profiles')->where('user_id', $actorId)->where('notifications_enabled', true)->exists()) {
            throw new RpcError('PUSH_DISABLED');
        }

        $deviceKeyHash = $params['p_device_key_hash'] ?? null;
        $pushToken = $params['p_push_token'] ?? null;
        $platform = $params['p_platform'] ?? null;
        if (! is_string($deviceKeyHash) || preg_match('/^[0-9a-f]{64}$/', $deviceKeyHash) !== 1
            || ! is_string($pushToken) || mb_strlen($pushToken) < 20 || mb_strlen($pushToken) > 4096
            || ! in_array($platform, ['android', 'ios'], true)) {
            throw new RpcError('INVALID_INPUT');
        }

        DB::table('user_devices')->upsert([[
            'id' => (string) Str::uuid(),
            'user_id' => $actorId,
            'device_key_hash' => $deviceKeyHash,
            'push_token' => $pushToken,
            'platform' => $platform,
            'created_at' => now(),
            'updated_at' => now(),
        ]], ['user_id', 'device_key_hash'], ['push_token', 'platform', 'updated_at']);

        return ['registered' => true];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function unregisterDevice(string $actorId, array $params): array
    {
        $deviceKeyHash = $params['p_device_key_hash'] ?? null;
        if (! is_string($deviceKeyHash) || preg_match('/^[0-9a-f]{64}$/', $deviceKeyHash) !== 1) {
            throw new RpcError('INVALID_INPUT');
        }

        DB::table('user_devices')->where('user_id', $actorId)->where('device_key_hash', $deviceKeyHash)->delete();

        return ['unregistered' => true];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    private function reportAndBlockFromNote(string $actorId, array $params, bool $reportUser): array
    {
        $noteId = $this->uuid($params, 'p_note_id');

        return DB::transaction(function () use ($actorId, $noteId, $params, $reportUser): array {
            $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
            if ($note === null || ! in_array($note->status, ['published', 'hidden'], true) || $note->author_id === $actorId) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            $type = $reportUser ? 'user' : 'note';
            $target = $reportUser ? (string) $note->author_id : $noteId;
            $report = $this->createReport(
                $actorId,
                $type,
                $target,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
            $this->createBlock($actorId, (string) $note->author_id, $noteId);

            return ['report_id' => $report['report_id'], 'blocked' => true];
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    private function reportAndBlockFromConversation(string $actorId, array $params, bool $reportUser): array
    {
        $conversationId = $this->uuid($params, 'p_conversation_id');

        return DB::transaction(function () use ($actorId, $conversationId, $params, $reportUser): array {
            $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
            if ($conversation === null || ! $this->isParticipant($conversation, $actorId)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }
            $targetId = $conversation->participant_low === $actorId
                ? (string) $conversation->participant_high
                : (string) $conversation->participant_low;
            $report = $this->createReport(
                $actorId,
                $reportUser ? 'user' : 'conversation',
                $reportUser ? $targetId : $conversationId,
                $params['p_reason'] ?? null,
                $params['p_description'] ?? null,
            );
            $this->createBlock($actorId, $targetId, null);

            return ['report_id' => $report['report_id'], 'blocked' => true];
        }, 3);
    }

    /** @return array{report_id: string, status: string} */
    private function createReport(string $actorId, string $targetType, string $targetId, mixed $reasonValue, mixed $descriptionValue): array
    {
        $reason = is_string($reasonValue) ? $reasonValue : null;
        if (! in_array($targetType, ['note', 'message', 'conversation', 'user'], true)
            || $targetType === 'user' && $targetId === $actorId
            || ! in_array($reason, self::REPORT_REASONS, true)) {
            throw new RpcError('INVALID_INPUT');
        }
        $description = $this->normalizeDescription($descriptionValue);
        $this->ensureReportTargetExists($actorId, $targetType, $targetId);

        DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
        $existing = DB::table('reports')->where('reporter_id', $actorId)
            ->where('target_type', $targetType)->where('target_id', $targetId)->first();
        if ($existing !== null) {
            return ['report_id' => (string) $existing->id, 'status' => $existing->status];
        }

        $reportCount = DB::table('reports')->where('reporter_id', $actorId)
            ->where('created_at', '>', now()->subHour())->count();
        if ($reportCount >= 10) {
            throw new RpcError('RATE_LIMITED', '', true, 429);
        }

        $reportId = (string) Str::uuid();
        try {
            DB::table('reports')->insert([
                'id' => $reportId,
                'reporter_id' => $actorId,
                'target_type' => $targetType,
                'target_id' => $targetId,
                'reason' => $reason,
                'description' => $description,
                'status' => 'pending',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (QueryException $error) {
            if (! $this->isDuplicateKey($error)) {
                throw $error;
            }
            $existing = DB::table('reports')->where('reporter_id', $actorId)
                ->where('target_type', $targetType)->where('target_id', $targetId)->first();
            if ($existing === null) {
                throw $error;
            }

            return ['report_id' => (string) $existing->id, 'status' => $existing->status];
        }

        return ['report_id' => $reportId, 'status' => 'pending'];
    }

    private function ensureReportTargetExists(string $actorId, string $targetType, string $targetId): void
    {
        $exists = match ($targetType) {
            'note' => DB::table('notes')->where('id', $targetId)
                ->where(function ($query) use ($actorId): void {
                    $query->where('status', 'published')->orWhere('author_id', $actorId);
                })->exists(),
            'message' => DB::table('messages as m')->join('conversations as c', 'c.id', '=', 'm.conversation_id')
                ->where('m.id', $targetId)->where(function ($query) use ($actorId): void {
                    $query->where('c.participant_low', $actorId)->orWhere('c.participant_high', $actorId);
                })->exists(),
            'conversation' => DB::table('conversations')->where('id', $targetId)
                ->where(function ($query) use ($actorId): void {
                    $query->where('participant_low', $actorId)->orWhere('participant_high', $actorId);
                })->exists(),
            'user' => DB::table('users')->where('id', $targetId)->where('id', '<>', $actorId)->exists(),
            default => false,
        };

        if (! $exists) {
            throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
        }
    }

    private function normalizeDescription(mixed $value): ?string
    {
        if ($value !== null && ! is_string($value)) {
            throw new RpcError('INVALID_INPUT');
        }
        $description = trim(str_replace(["\r\n", "\r"], "\n", $value ?? ''));
        if (class_exists(\Normalizer::class)) {
            $description = \Normalizer::normalize($description, \Normalizer::FORM_C) ?: $description;
        }
        if (mb_strlen($description) > 500 || strlen($description) > 3072) {
            throw new RpcError('INVALID_INPUT');
        }

        return $description === '' ? null : $description;
    }

    private function createBlock(string $actorId, string $targetId, ?string $sourceNoteId): void
    {
        if ($actorId === $targetId) {
            throw new RpcError('INVALID_INPUT');
        }
        DB::table('blocks')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'blocker_id' => $actorId,
            'blocked_id' => $targetId,
            'source_note_id' => $sourceNoteId,
            'created_at' => now(),
        ]);

        $conversations = DB::table('conversations')->where('status', 'active')
            ->where(function ($participants) use ($actorId, $targetId): void {
                $participants->where(function ($pair) use ($actorId, $targetId): void {
                    $pair->where('participant_low', $actorId)->where('participant_high', $targetId);
                })->orWhere(function ($pair) use ($actorId, $targetId): void {
                    $pair->where('participant_low', $targetId)->where('participant_high', $actorId);
                });
            })->lockForUpdate()->get(['id', 'participant_low', 'participant_high']);

        foreach ($conversations as $conversation) {
            DB::table('conversations')->where('id', $conversation->id)->update([
                'status' => 'blocked',
                'updated_at' => now(),
            ]);
            PrivateSignal::dispatch('conversation:'.$conversation->id, 'conversation_blocked');
            PrivateSignal::dispatch('user:'.$conversation->participant_low, 'inbox_updated');
            PrivateSignal::dispatch('user:'.$conversation->participant_high, 'inbox_updated');
        }
    }

    private function isParticipant(object $conversation, string $actorId): bool
    {
        return (string) $conversation->participant_low === $actorId || (string) $conversation->participant_high === $actorId;
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

    private function isDuplicateKey(QueryException $error): bool
    {
        return (string) ($error->errorInfo[1] ?? '') === '1062';
    }
}
