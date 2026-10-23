<?php

namespace App\Services;

use App\Events\PrivateSignal;
use App\Exceptions\RpcError;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class EngagementOperations
{
    public function __construct(
        private readonly AccountService $accounts,
        private readonly NotificationService $notifications,
    ) {}

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function sendEncouragement(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $requestId = $this->uuid($params, 'p_client_request_id');
        $template = $params['p_template_key'] ?? null;
        if (! in_array($template, ['LISTEN', 'TOMORROW', 'TRIED', 'THANKS', 'HUG'], true)) {
            throw new RpcError('INVALID_INPUT');
        }
        $payloadHash = $this->payloadHash(['note_id' => $noteId, 'template_key' => $template]);

        try {
            return DB::transaction(function () use ($actorId, $noteId, $requestId, $template, $payloadHash): array {
                DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
                $previous = $this->idempotentResult($actorId, 'send_encouragement', $requestId, $payloadHash);
                if ($previous !== null) {
                    return $previous;
                }

                $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
                if ($note === null || $note->status !== 'published') {
                    throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
                }
                if ($note->author_id === $actorId) {
                    throw new RpcError('INVALID_INPUT', 'Bạn không thể tự gửi lời động viên cho giấy của mình.');
                }
                if ($this->isBlockedBetween($actorId, (string) $note->author_id)) {
                    throw new RpcError('BLOCKED', '', false, 403);
                }
                if (DB::table('encouragements')->where('note_id', $noteId)->where('sender_id', $actorId)->exists()) {
                    throw new RpcError('ALREADY_ENCOURAGED', '', false, 409);
                }

                $id = (string) Str::uuid();
                $createdAt = now();
                DB::table('encouragements')->insert([
                    'id' => $id,
                    'note_id' => $noteId,
                    'sender_id' => $actorId,
                    'template_key' => $template,
                    'created_at' => $createdAt,
                ]);
                $this->notifications->create((string) $note->author_id, 'encouragement', $id);
                PrivateSignal::dispatch('user:'.$note->author_id, 'inbox_updated');
                $payload = ['id' => $id, 'created_at' => $createdAt->toISOString()];
                $this->rememberIdempotentResult($actorId, 'send_encouragement', $requestId, $payloadHash, ['data' => $payload]);

                return $payload;
            }, 3);
        } catch (QueryException $error) {
            if ($this->isDuplicateKey($error)) {
                throw new RpcError('ALREADY_ENCOURAGED', '', false, 409);
            }
            throw $error;
        }
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function startConversation(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $requestId = $this->uuid($params, 'p_client_request_id');
        $payloadHash = $this->payloadHash(['note_id' => $noteId]);

        return DB::transaction(function () use ($actorId, $noteId, $requestId, $payloadHash): array {
            DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
            $previous = $this->idempotentResult($actorId, 'start_conversation_from_note', $requestId, $payloadHash);
            if ($previous !== null) {
                return $previous;
            }

            $note = DB::table('notes')->where('id', $noteId)->lockForUpdate()->first();
            if ($note === null || $note->status !== 'published') {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            if ($note->author_id === $actorId) {
                throw new RpcError('INVALID_INPUT');
            }
            if (! $note->allow_chat) {
                throw new RpcError('CHAT_DISABLED');
            }
            if ($this->isBlockedBetween($actorId, (string) $note->author_id)) {
                throw new RpcError('BLOCKED', '', false, 403);
            }

            [$low, $high] = strcmp($actorId, (string) $note->author_id) < 0
                ? [$actorId, (string) $note->author_id]
                : [(string) $note->author_id, $actorId];
            $conversationId = (string) Str::uuid();
            $createdAt = now();
            $created = DB::table('conversations')->insertOrIgnore([
                'id' => $conversationId,
                'participant_low' => $low,
                'participant_high' => $high,
                'source_note_id' => $noteId,
                'created_by' => $actorId,
                'status' => 'active',
                'streak_count' => 0,
                'created_at' => $createdAt,
                'updated_at' => $createdAt,
            ]) === 1;
            $conversation = DB::table('conversations')->where('participant_low', $low)
                ->where('participant_high', $high)->lockForUpdate()->first();
            if ($conversation === null) {
                throw new RpcError('SERVICE_UNAVAILABLE', '', true, 503);
            }
            if ($conversation->status !== 'active') {
                throw new RpcError('CLOSED', '', false, 409);
            }

            $remaining = $conversation->last_sender_id === $actorId
                ? max(0, 3 - (int) $conversation->streak_count)
                : 3;
            $payload = [
                'conversation_id' => (string) $conversation->id,
                'created' => $created,
                'can_send' => $remaining > 0,
                'remaining_outbound' => $remaining,
            ];
            $this->rememberIdempotentResult($actorId, 'start_conversation_from_note', $requestId, $payloadHash, ['data' => $payload]);

            return $payload;
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function sendMessage(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $conversationId = $this->uuid($params, 'p_conversation_id');
        $requestId = $this->uuid($params, 'p_client_request_id');
        $body = $this->normalizeBody($params['p_body'] ?? null);
        $payloadHash = $this->payloadHash(['conversation_id' => $conversationId, 'body' => $body]);

        try {
            return DB::transaction(function () use ($actorId, $conversationId, $requestId, $body, $payloadHash): array {
                DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
                $previous = $this->idempotentResult($actorId, 'send_message', $requestId, $payloadHash);
                if ($previous !== null) {
                    return $previous;
                }
                $existing = DB::table('messages')->where('sender_id', $actorId)->where('client_request_id', $requestId)->first();
                if ($existing !== null) {
                    if ($existing->conversation_id !== $conversationId || $existing->body !== $body) {
                        throw new RpcError('IDEMPOTENCY_CONFLICT', '', false, 409);
                    }
                    $conversation = DB::table('conversations')->where('id', $conversationId)->first();
                    $remaining = $conversation->last_sender_id === $actorId
                        ? max(0, 3 - (int) $conversation->streak_count)
                        : 3;

                    return [
                        'message_id' => (string) $existing->id,
                        'created_at' => $existing->created_at,
                        'remaining_outbound' => $remaining,
                        'status' => $existing->status,
                    ];
                }

                $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
                if ($conversation === null || ! in_array($actorId, [$conversation->participant_low, $conversation->participant_high], true)) {
                    throw new RpcError('NOT_PARTICIPANT', '', false, 403);
                }
                if ($conversation->status !== 'active') {
                    throw new RpcError('CLOSED', '', false, 409);
                }
                $recipientId = $conversation->participant_low === $actorId
                    ? (string) $conversation->participant_high
                    : (string) $conversation->participant_low;
                if ($this->isBlockedBetween($actorId, $recipientId)) {
                    throw new RpcError('BLOCKED', '', false, 403);
                }

                $recentCount = DB::table('rate_limit_events')->where('actor_id', $actorId)
                    ->where('operation', 'send_message')->where('occurred_at', '>', now()->subMinute())->count();
                if ($recentCount >= 30) {
                    throw new RpcError('RATE_LIMITED', '', true, 429);
                }
                DB::table('rate_limit_events')->insert([
                    'actor_id' => $actorId,
                    'operation' => 'send_message',
                    'occurred_at' => now(),
                ]);

                $newStreak = $conversation->last_sender_id === $actorId ? (int) $conversation->streak_count + 1 : 1;
                if ($newStreak > 3) {
                    throw new RpcError('MESSAGE_LIMIT_REACHED', '', false, 409);
                }
                $moderationMode = DB::table('app_settings')->where('setting_key', 'moderation_mode')->value('setting_value');
                $risk = $this->contentHasContactInfo($body);
                $status = $moderationMode === 'hold_all' || $risk ? 'pending_review' : 'delivered';
                $messageId = (string) Str::uuid();
                $createdAt = now();
                DB::table('messages')->insert([
                    'id' => $messageId,
                    'conversation_id' => $conversationId,
                    'sender_id' => $actorId,
                    'client_request_id' => $requestId,
                    'body' => $body,
                    'status' => $status,
                    'created_at' => $createdAt,
                ]);
                DB::table('conversations')->where('id', $conversationId)->update([
                    'last_sender_id' => $actorId,
                    'streak_count' => $newStreak,
                    'last_message_at' => $createdAt,
                    'updated_at' => $createdAt,
                ]);

                if ($status === 'delivered') {
                    $this->notifications->create($recipientId, 'message', $messageId, $conversationId);
                    PrivateSignal::dispatch('conversation:'.$conversationId, 'conversation_updated');
                    PrivateSignal::dispatch('user:'.$recipientId, 'inbox_updated');
                } else {
                    $reason = $moderationMode === 'hold_all' ? 'HOLD_ALL_MESSAGE' : 'CONTACT_OR_LINK';
                    DB::table('message_moderation_events')->insert([
                        'id' => (string) Str::uuid(),
                        'message_id' => $messageId,
                        'actor_id' => $actorId,
                        'reason_code' => $reason,
                        'created_at' => $createdAt,
                    ]);
                    DB::table('moderation_queue')->upsert([[
                        'id' => (string) Str::uuid(),
                        'target_type' => 'message',
                        'target_id' => $messageId,
                        'reason_code' => $reason,
                        'queue_status' => 'pending',
                        'created_at' => $createdAt,
                        'updated_at' => $createdAt,
                    ]], ['target_type', 'target_id'], ['reason_code', 'queue_status', 'updated_at']);
                }

                $payload = [
                    'message_id' => $messageId,
                    'created_at' => $createdAt->toISOString(),
                    'remaining_outbound' => 3 - $newStreak,
                    'status' => $status,
                ];
                $this->rememberIdempotentResult($actorId, 'send_message', $requestId, $payloadHash, ['data' => $payload]);

                return $payload;
            }, 3);
        } catch (QueryException $error) {
            if ($this->isDuplicateKey($error)) {
                throw new RpcError('IDEMPOTENCY_CONFLICT', '', false, 409);
            }
            throw $error;
        }
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getMessages(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $conversationId = $this->uuid($params, 'p_conversation_id');
        $beforeAt = $params['p_before_created_at'] ?? null;
        $beforeId = $params['p_before_id'] ?? null;
        $limit = max(1, min(50, (int) ($params['p_limit'] ?? 30)));
        if (($beforeAt === null) !== ($beforeId === null)
            || ($beforeId !== null && ! Str::isUuid((string) $beforeId))) {
            throw new RpcError('INVALID_INPUT');
        }

        $conversation = DB::table('conversations')->where('id', $conversationId)->first();
        if ($conversation === null || ! in_array($actorId, [$conversation->participant_low, $conversation->participant_high], true)) {
            throw new RpcError('NOT_PARTICIPANT', '', false, 403);
        }
        $sourceNoteContent = DB::table('notes')->where('id', $conversation->source_note_id)
            ->where('status', 'published')->value('content');
        DB::table('notifications')->where('recipient_id', $actorId)->where('conversation_id', $conversationId)
            ->where('notification_type', 'message')->whereNull('read_at')->update(['read_at' => now()]);

        $remaining = $conversation->last_sender_id === $actorId
            ? max(0, 3 - (int) $conversation->streak_count)
            : 3;
        $query = DB::table('messages')->where('conversation_id', $conversationId)
            ->where(function ($visible) use ($actorId): void {
                $visible->where('status', 'delivered')
                    ->orWhere(function ($own) use ($actorId): void {
                        $own->where('sender_id', $actorId)->whereIn('status', ['pending_review', 'rejected', 'hidden']);
                    });
            });
        if ($beforeAt !== null) {
            $query->where(fn ($cursor) => $cursor->where('created_at', '<', $beforeAt)
                ->orWhere(fn ($sameTime) => $sameTime->where('created_at', $beforeAt)->where('id', '<', $beforeId)));
        }
        $limited = $query->orderByDesc('created_at')->orderByDesc('id')->limit($limit + 1)
            ->get(['id', 'conversation_id', 'sender_id', 'body', 'status', 'created_at']);
        $hasMore = $limited->count() > $limit;
        $items = $limited->take($limit)->map(fn (object $message): array => [
            'id' => (string) $message->id,
            'conversation_id' => (string) $message->conversation_id,
            'body' => $message->body,
            'is_mine' => $message->sender_id === $actorId,
            'created_at' => $message->created_at,
            'status' => $message->status,
        ])->values()->all();
        $oldest = $items === [] ? null : $items[array_key_last($items)];

        return [
            'items' => $items,
            'remaining_outbound' => $remaining,
            'can_send' => $conversation->status === 'active' && $remaining > 0,
            'status' => $conversation->status,
            'source_note_content' => $sourceNoteContent,
            'next_cursor' => $hasMore && $oldest !== null
                ? ['created_at' => $oldest['created_at'], 'id' => $oldest['id']]
                : null,
        ];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getInbox(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $kind = $params['p_kind'] ?? null;
        $cursorAt = $params['p_cursor_created_at'] ?? null;
        $cursorId = $params['p_cursor_id'] ?? null;
        $limit = max(1, min(30, (int) ($params['p_limit'] ?? 20)));
        if (! in_array($kind, ['encouragements', 'chats'], true)
            || (($cursorAt === null) !== ($cursorId === null))
            || ($cursorId !== null && ! Str::isUuid((string) $cursorId))) {
            throw new RpcError('INVALID_INPUT');
        }

        if ($kind === 'encouragements') {
            $query = DB::table('encouragements as e')
                ->join('notes as n', function ($join) use ($actorId): void {
                    $join->on('n.id', '=', 'e.note_id')->where('n.author_id', '=', $actorId);
                })
                ->leftJoin('notifications as notification', function ($join) use ($actorId): void {
                    $join->on('notification.source_id', '=', 'e.id')
                        ->where('notification.recipient_id', '=', $actorId)
                        ->where('notification.notification_type', '=', 'encouragement');
                });
            if ($cursorAt !== null) {
                $query->where(fn ($cursor) => $cursor->where('e.created_at', '<', $cursorAt)
                    ->orWhere(fn ($sameTime) => $sameTime->where('e.created_at', $cursorAt)->where('e.id', '<', $cursorId)));
            }
            $limited = $query->orderByDesc('e.created_at')->orderByDesc('e.id')->limit($limit + 1)
                ->get(['e.id', 'e.note_id', 'e.template_key', 'e.created_at', 'n.cell_x', 'n.cell_y', 'notification.id as notification_id', 'notification.read_at']);
            $hasMore = $limited->count() > $limit;
            $items = $limited->take($limit)->map(fn (object $item): array => [
                'id' => (string) $item->id,
                'note_id' => (string) $item->note_id,
                'template_key' => $item->template_key,
                'created_at' => $item->created_at,
                'cell_x' => (int) $item->cell_x,
                'cell_y' => (int) $item->cell_y,
                'notification_id' => $item->notification_id === null ? null : (string) $item->notification_id,
                'is_read' => $item->read_at !== null,
            ])->values()->all();
        } else {
            $query = DB::table('conversations as c')
                ->join('messages as m', function ($join): void {
                    $join->on('m.conversation_id', '=', 'c.id')->where('m.status', '=', 'delivered');
                })
                ->where(function ($participants) use ($actorId): void {
                    $participants->where('c.participant_low', $actorId)->orWhere('c.participant_high', $actorId);
                })
                ->where('c.status', 'active')
                ->whereNotExists(function ($latest) {
                    $latest->selectRaw('1')->from('messages as newer')
                        ->whereColumn('newer.conversation_id', 'm.conversation_id')
                        ->where('newer.status', 'delivered')
                        ->where(function ($order): void {
                            $order->whereColumn('newer.created_at', '>', 'm.created_at')
                                ->orWhere(function ($sameTime): void {
                                    $sameTime->whereColumn('newer.created_at', '=', 'm.created_at')
                                        ->whereColumn('newer.id', '>', 'm.id');
                                });
                        });
                });
            if ($cursorAt !== null) {
                $query->where(fn ($cursor) => $cursor->where('m.created_at', '<', $cursorAt)
                    ->orWhere(fn ($sameTime) => $sameTime->where('m.created_at', $cursorAt)->where('c.id', '<', $cursorId)));
            }
            $limited = $query->orderByDesc('m.created_at')->orderByDesc('c.id')->limit($limit + 1)
                ->get(['c.id', 'c.last_sender_id', 'c.streak_count', 'm.created_at as last_message_at', 'm.sender_id as last_sender', 'm.body as last_message_body']);
            $hasMore = $limited->count() > $limit;
            $items = $limited->take($limit)->map(function (object $item) use ($actorId): array {
                $unread = (int) DB::table('notifications')->where('recipient_id', $actorId)
                    ->where('conversation_id', $item->id)->whereNull('read_at')->count();

                return [
                    'conversation_id' => (string) $item->id,
                    'last_message_at' => $item->last_message_at,
                    'last_message_is_mine' => $item->last_sender === $actorId,
                    'remaining_outbound' => $item->last_sender_id === $actorId ? max(0, 3 - (int) $item->streak_count) : 3,
                    'last_message_preview' => $item->last_message_body,
                    'unread_count' => $unread,
                ];
            })->values()->all();
        }

        $oldest = $items === [] ? null : $items[array_key_last($items)];
        $cursorDateKey = $kind === 'encouragements' ? 'created_at' : 'last_message_at';
        $cursorIdKey = $kind === 'encouragements' ? 'id' : 'conversation_id';

        return [
            'items' => $items,
            'next_cursor' => $hasMore && $oldest !== null
                ? ['created_at' => $oldest[$cursorDateKey], 'id' => $oldest[$cursorIdKey]]
                : null,
        ];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function closeConversation(string $actorId, array $params): array
    {
        $conversationId = $this->uuid($params, 'p_conversation_id');

        return DB::transaction(function () use ($actorId, $conversationId): array {
            $conversation = DB::table('conversations')->where('id', $conversationId)->lockForUpdate()->first();
            if ($conversation === null || ! in_array($actorId, [$conversation->participant_low, $conversation->participant_high], true)) {
                throw new RpcError('NOT_PARTICIPANT', '', false, 403);
            }
            if ($conversation->status === 'active') {
                DB::table('conversations')->where('id', $conversationId)->update(['status' => 'closed_by_user', 'updated_at' => now()]);

                return ['status' => 'closed_by_user'];
            }

            return ['status' => $conversation->status];
        }, 3);
    }

    private function requireEligible(string $actorId): void
    {
        if (! $this->accounts->isEligible($actorId)) {
            throw new RpcError('NOT_ELIGIBLE', 'Hoàn tất phần xác nhận tài khoản trước.', false, 403);
        }
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

    private function normalizeBody(mixed $value): string
    {
        if (! is_string($value)) {
            throw new RpcError('INVALID_INPUT');
        }
        $body = trim(str_replace(["\r\n", "\r"], "\n", $value));
        if (class_exists(\Normalizer::class)) {
            $body = \Normalizer::normalize($body, \Normalizer::FORM_C) ?: $body;
        }
        if ($body === '' || mb_strlen($body) > 500 || strlen($body) > 3072) {
            throw new RpcError('INVALID_INPUT', 'Tin nhắn cần có nội dung và không quá 500 ký tự.');
        }

        return $body;
    }

    private function contentHasContactInfo(string $content): bool
    {
        return preg_match('/(https?:\/\/|www\.|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|\+?[0-9][0-9 .()\-]{7,}[0-9])/iu', $content) === 1;
    }

    private function isBlockedBetween(string $first, string $second): bool
    {
        return DB::table('blocks')->where(function ($query) use ($first, $second): void {
            $query->where(fn ($pair) => $pair->where('blocker_id', $first)->where('blocked_id', $second))
                ->orWhere(fn ($pair) => $pair->where('blocker_id', $second)->where('blocked_id', $first));
        })->exists();
    }

    /** @param array<string, mixed> $value */
    private function payloadHash(array $value): string
    {
        return hash('sha256', json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    }

    /** @return array<string, mixed>|null */
    private function idempotentResult(string $actorId, string $operation, string $requestId, string $payloadHash): ?array
    {
        $previous = DB::table('request_idempotency')->where('actor_id', $actorId)
            ->where('operation', $operation)->where('request_id', $requestId)->first();
        if ($previous === null) {
            return null;
        }
        if (! hash_equals($previous->payload_hash, $payloadHash)) {
            throw new RpcError('IDEMPOTENCY_CONFLICT', '', false, 409);
        }

        $decoded = json_decode($previous->result, true);
        if (! is_array($decoded) || ! isset($decoded['data']) || ! is_array($decoded['data'])) {
            throw new RpcError('SERVICE_UNAVAILABLE', '', true, 503);
        }

        return $decoded['data'];
    }

    /** @param array<string, mixed> $oldEnvelope */
    private function rememberIdempotentResult(string $actorId, string $operation, string $requestId, string $payloadHash, array $oldEnvelope): void
    {
        DB::table('request_idempotency')->insert([
            'actor_id' => $actorId,
            'operation' => $operation,
            'request_id' => $requestId,
            'payload_hash' => $payloadHash,
            'result' => json_encode($oldEnvelope, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
            'created_at' => now(),
            'expires_at' => now()->addDays(30),
        ]);
    }

    private function isDuplicateKey(QueryException $error): bool
    {
        return in_array((string) ($error->errorInfo[0] ?? ''), ['23000', '23505'], true);
    }
}
