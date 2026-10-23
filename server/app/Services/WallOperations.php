<?php

namespace App\Services;

use App\Events\PrivateSignal;
use App\Exceptions\RpcError;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class WallOperations
{
    public function __construct(private readonly AccountService $accounts) {}

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getWallTiles(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $minX = $this->integer($params, 'p_min_cell_x');
        $maxX = $this->integer($params, 'p_max_cell_x');
        $minY = $this->integer($params, 'p_min_cell_y');
        $maxY = $this->integer($params, 'p_max_cell_y');
        $cursorY = $params['p_cursor_cell_y'] ?? null;
        $cursorX = $params['p_cursor_cell_x'] ?? null;
        $cursorId = $params['p_cursor_id'] ?? null;
        $limit = max(1, min(200, (int) ($params['p_limit'] ?? 200)));

        if ($minX > $maxX || $minY > $maxY || $maxX - $minX + 1 > 32 || $maxY - $minY + 1 > 32) {
            throw new RpcError('INVALID_VIEWPORT');
        }

        $hasCursor = $cursorY !== null && $cursorX !== null && $cursorId !== null;
        if (($cursorY !== null || $cursorX !== null || $cursorId !== null) && ! $hasCursor) {
            throw new RpcError('INVALID_VIEWPORT');
        }
        if ($hasCursor && ! Str::isUuid((string) $cursorId)) {
            throw new RpcError('INVALID_VIEWPORT');
        }

        $query = DB::table('notes')
            ->where('status', 'published')
            ->whereBetween('cell_x', [$minX, $maxX])
            ->whereBetween('cell_y', [$minY, $maxY]);

        if ($hasCursor) {
            $query->where(function ($cursorQuery) use ($cursorY, $cursorX, $cursorId): void {
                $cursorQuery->where('cell_y', '>', (int) $cursorY)
                    ->orWhere(function ($sameY) use ($cursorY, $cursorX): void {
                        $sameY->where('cell_y', (int) $cursorY)->where('cell_x', '>', (int) $cursorX);
                    })
                    ->orWhere(function ($sameCell) use ($cursorY, $cursorX, $cursorId): void {
                        $sameCell->where('cell_y', (int) $cursorY)
                            ->where('cell_x', (int) $cursorX)
                            ->where('id', '>', (string) $cursorId);
                    });
            });
        }

        $limited = $query->orderBy('cell_y')->orderBy('cell_x')->orderBy('id')->limit($limit + 1)->get([
            'id', 'cell_x', 'cell_y', 'paper_color', 'style_seed', 'published_at',
        ]);
        $hasMore = $limited->count() > $limit;
        $items = $limited->take($limit)->map(fn (object $note): array => [
            'id' => (string) $note->id,
            'cell_x' => (int) $note->cell_x,
            'cell_y' => (int) $note->cell_y,
            'paper_color' => $note->paper_color,
            'style_seed' => (int) $note->style_seed,
            'published_at' => $note->published_at,
        ])->values()->all();
        $last = $items === [] ? null : $items[array_key_last($items)];
        $cursor = $hasMore && $last !== null ? [
            'cell_y' => $last['cell_y'],
            'cell_x' => $last['cell_x'],
            'id' => $last['id'],
        ] : null;
        $revision = (int) (DB::table('wall_regions')
            ->whereBetween('tile_x', [$this->floorDiv($minX, 8), $this->floorDiv($maxX, 8)])
            ->whereBetween('tile_y', [$this->floorDiv($minY, 8), $this->floorDiv($maxY, 8)])
            ->max('revision') ?? 0);

        return ['items' => $items, 'next_cursor' => $cursor, 'revision' => $revision];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getWallDensity(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $minX = $this->integer($params, 'p_min_tile_x');
        $maxX = $this->integer($params, 'p_max_tile_x');
        $minY = $this->integer($params, 'p_min_tile_y');
        $maxY = $this->integer($params, 'p_max_tile_y');

        if ($minX > $maxX || $minY > $maxY || $maxX - $minX + 1 > 32 || $maxY - $minY + 1 > 32) {
            throw new RpcError('INVALID_VIEWPORT');
        }

        $items = DB::table('wall_regions')
            ->whereBetween('tile_x', [$minX, $maxX])
            ->whereBetween('tile_y', [$minY, $maxY])
            ->where('published_count', '>', 0)
            ->orderBy('tile_y')->orderBy('tile_x')
            ->get(['tile_x', 'tile_y', 'published_count'])
            ->map(fn (object $region): array => [
                'tile_x' => (int) $region->tile_x,
                'tile_y' => (int) $region->tile_y,
                'published_count' => (int) $region->published_count,
            ])->all();

        return ['items' => $items];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getNoteDetail(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $note = DB::table('notes')->where('id', $noteId)
            ->where(fn ($query) => $query->where('status', 'published')->orWhere('author_id', $actorId))
            ->first();

        if ($note === null) {
            throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
        }

        $isOwner = $note->author_id === $actorId;
        $blocked = ! $isOwner && $this->isBlockedBetween($actorId, (string) $note->author_id);
        $alreadyEncouraged = ! $isOwner && DB::table('encouragements')->where('note_id', $noteId)->where('sender_id', $actorId)->exists();
        $interacted = DB::table('encouragements')->where('note_id', $noteId)->exists()
            || DB::table('conversations')->where('source_note_id', $noteId)->exists();
        $canEdit = $isOwner && in_array($note->status, ['pending_review', 'published'], true)
            && now()->lessThan(Carbon::parse($note->created_at)->addMinutes(30))
            && ! $interacted;

        return [
            'id' => $noteId,
            'content' => $note->content,
            'paper_color' => $note->paper_color,
            'published_at' => $note->published_at,
            'status' => $note->status,
            'is_owner' => $isOwner,
            'already_encouraged' => $alreadyEncouraged,
            'allow_chat' => (bool) $note->allow_chat,
            'can_encourage' => ! $isOwner && ! $blocked && ! $alreadyEncouraged && $note->status === 'published',
            'can_start_chat' => ! $isOwner && ! $blocked && (bool) $note->allow_chat && $note->status === 'published',
            'can_edit' => $canEdit,
            'can_delete' => $isOwner && $note->status !== 'deleted',
        ];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getDiscoveryTarget(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $excluded = $params['p_exclude_regions'] ?? [];
        if (! is_array($excluded) || count($excluded) > 10) {
            throw new RpcError('INVALID_INPUT');
        }

        $excludeKeys = [];
        foreach ($excluded as $region) {
            if (! is_array($region) || ! isset($region['tile_x'], $region['tile_y'])
                || filter_var($region['tile_x'], FILTER_VALIDATE_INT) === false
                || filter_var($region['tile_y'], FILTER_VALIDATE_INT) === false) {
                throw new RpcError('INVALID_INPUT');
            }
            $excludeKeys[] = (int) $region['tile_x'].':'.(int) $region['tile_y'];
        }

        $regions = DB::table('wall_regions')->where('published_count', '>', 0)->get(['tile_x', 'tile_y', 'published_count']);
        $candidates = [];
        foreach ($regions as $region) {
            $tileX = (int) $region->tile_x;
            $tileY = (int) $region->tile_y;
            $notes = DB::table('notes')->whereIn('status', ['pending_review', 'published', 'hidden'])
                ->whereBetween('cell_x', [$tileX * 8, $tileX * 8 + 7])
                ->whereBetween('cell_y', [$tileY * 8, $tileY * 8 + 7])
                ->get(['id', 'status', 'published_at']);
            $available = 64 - $notes->count();
            if ($available < 3 || $notes->count() > 61) {
                continue;
            }
            $hasUnencouraged = $notes->contains(fn (object $note): bool => $note->status === 'published'
                && ! DB::table('encouragements')->where('note_id', $note->id)->exists());
            $hasRecent = $notes->contains(fn (object $note): bool => $note->status === 'published'
                && $note->published_at !== null
                && Carbon::parse($note->published_at)->greaterThanOrEqualTo(now()->subDays(7)));
            $candidates[] = [
                'tile_x' => $tileX,
                'tile_y' => $tileY,
                'available_cells' => $available,
                'has_unencouraged' => $hasUnencouraged,
                'has_recent' => $hasRecent,
                'excluded' => in_array($tileX.':'.$tileY, $excludeKeys, true),
            ];
        }

        $mode = random_int(0, 9999) / 10000;
        $weighted = array_values(array_filter($candidates, function (array $candidate) use ($mode): bool {
            if ($mode < 0.40) {
                return $candidate['has_unencouraged'];
            }
            if ($mode < 0.75) {
                return $candidate['has_recent'];
            }

            return true;
        }));
        $pool = array_values(array_filter($weighted, fn (array $candidate): bool => ! $candidate['excluded']));
        if ($pool === []) {
            $pool = $candidates;
        }
        if ($pool === []) {
            throw new RpcError('EMPTY_WORLD', 'Chưa có vùng tường phù hợp để khám phá.', true, 409);
        }

        $selected = $pool[random_int(0, count($pool) - 1)];

        return [
            'tile_x' => $selected['tile_x'],
            'tile_y' => $selected['tile_y'],
            'camera_world_x' => $selected['tile_x'] * 1440 + 720,
            'camera_world_y' => $selected['tile_y'] * 1440 + 720,
            'available_cells_estimate' => $selected['available_cells'],
        ];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function suggestPlacementRegions(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $nearX = $this->integer($params, 'p_near_cell_x');
        $nearY = $this->integer($params, 'p_near_cell_y');
        $candidates = [];
        for ($x = $nearX - 8; $x <= $nearX + 8; $x++) {
            for ($y = $nearY - 8; $y <= $nearY + 8; $y++) {
                if (! DB::table('active_note_cells')->where('cell_x', $x)->where('cell_y', $y)->exists()) {
                    $candidates[] = ['cell_x' => $x, 'cell_y' => $y, 'distance' => abs($x - $nearX) + abs($y - $nearY)];
                }
            }
        }

        usort($candidates, fn (array $a, array $b): int => ($a['distance'] <=> $b['distance'])
            ?: ($a['cell_y'] <=> $b['cell_y']) ?: ($a['cell_x'] <=> $b['cell_x']));

        return ['items' => array_map(
            fn (array $item): array => ['cell_x' => $item['cell_x'], 'cell_y' => $item['cell_y']],
            array_slice($candidates, 0, 3),
        )];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function placeNote(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $content = $this->normalizeContent($params['p_content'] ?? null, 1000, 6144);
        $paperColor = $params['p_paper_color'] ?? null;
        $allowChat = $params['p_allow_chat'] ?? null;
        $cellX = $this->integer($params, 'p_cell_x');
        $cellY = $this->integer($params, 'p_cell_y');
        $requestId = $this->uuid($params, 'p_client_request_id');

        if (! in_array($paperColor, ['pink', 'butter', 'sage', 'blue', 'lilac'], true) || ! is_bool($allowChat)) {
            throw new RpcError('INVALID_INPUT', 'Hãy kiểm tra nội dung và lựa chọn của bạn.');
        }

        $payloadHash = hash('sha256', json_encode([
            'content' => $content,
            'paper_color' => $paperColor,
            'allow_chat' => $allowChat,
            'cell_x' => $cellX,
            'cell_y' => $cellY,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));

        try {
            return DB::transaction(function () use ($actorId, $content, $paperColor, $allowChat, $cellX, $cellY, $requestId, $payloadHash): array {
                DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
                $previous = $this->idempotentResult($actorId, 'place_note', $requestId, $payloadHash);
                if ($previous !== null) {
                    return $previous;
                }

                $today = now('Asia/Ho_Chi_Minh')->toDateString();
                if (DB::table('daily_note_creations')->where('user_id', $actorId)->where('creation_day_vn', $today)->exists()) {
                    throw new RpcError('DAILY_LIMIT', '', false, 429);
                }

                $moderationMode = DB::table('app_settings')->where('setting_key', 'moderation_mode')->value('setting_value');
                $risk = $this->contentHasContactInfo($content);
                $status = $moderationMode === 'hold_all' || $risk ? 'pending_review' : 'published';
                $noteId = (string) Str::uuid();
                $createdAt = now();

                DB::table('daily_note_creations')->insert([
                    'user_id' => $actorId,
                    'creation_day_vn' => $today,
                    'note_id' => $noteId,
                    'created_at' => $createdAt,
                ]);
                DB::table('notes')->insert([
                    'id' => $noteId,
                    'author_id' => $actorId,
                    'content' => $content,
                    'paper_color' => $paperColor,
                    'style_seed' => random_int(0, 2147483646),
                    'cell_x' => $cellX,
                    'cell_y' => $cellY,
                    'allow_chat' => $allowChat,
                    'status' => $status,
                    'published_at' => $status === 'published' ? $createdAt : null,
                    'content_version' => 1,
                    'created_at' => $createdAt,
                    'updated_at' => $createdAt,
                ]);
                DB::table('active_note_cells')->insert([
                    'cell_x' => $cellX,
                    'cell_y' => $cellY,
                    'note_id' => $noteId,
                ]);

                if ($status === 'pending_review') {
                    $reason = $moderationMode === 'hold_all' ? 'HOLD_ALL' : 'AUTOMATED_SIGNAL';
                    $this->enqueueNoteForModeration($noteId, $reason);
                    $this->recordNoteModeration($noteId, $actorId, null, 'pending_review', $reason);
                } else {
                    $this->syncPublishedRegion($cellX, $cellY);
                }

                $payload = [
                    'note_id' => $noteId,
                    'status' => $status,
                    'cell_x' => $cellX,
                    'cell_y' => $cellY,
                    'published_at' => $status === 'published' ? $createdAt->toISOString() : null,
                ];
                $this->rememberIdempotentResult($actorId, 'place_note', $requestId, $payloadHash, ['data' => $payload]);

                return $payload;
            }, 3);
        } catch (QueryException $error) {
            if (in_array((string) ($error->errorInfo[0] ?? ''), ['23000', '23505'], true)) {
                throw new RpcError('SLOT_OCCUPIED', 'Vị trí này vừa có một tờ giấy khác.', true, 409);
            }
            throw $error;
        }
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function getMyNotes(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $cursorAt = $params['p_cursor_created_at'] ?? null;
        $cursorId = $params['p_cursor_id'] ?? null;
        $limit = max(1, min(30, (int) ($params['p_limit'] ?? 20)));
        if (($cursorAt === null) !== ($cursorId === null)
            || ($cursorId !== null && ! Str::isUuid((string) $cursorId))) {
            throw new RpcError('INVALID_INPUT');
        }

        $query = DB::table('notes')->where('author_id', $actorId);
        if ($cursorAt !== null) {
            $query->where(fn ($cursorQuery) => $cursorQuery->where('created_at', '<', $cursorAt)
                ->orWhere(fn ($sameTime) => $sameTime->where('created_at', $cursorAt)->where('id', '<', $cursorId)));
        }
        $limited = $query->orderByDesc('created_at')->orderByDesc('id')->limit($limit + 1)->get([
            'id', 'content', 'paper_color', 'status', 'cell_x', 'cell_y', 'created_at', 'allow_chat',
        ]);
        $noteIds = $limited->pluck('id')->all();
        $interactedNoteIds = DB::table('encouragements')
            ->whereIn('note_id', $noteIds)
            ->distinct()
            ->pluck('note_id')
            ->merge(DB::table('conversations')
                ->whereIn('source_note_id', $noteIds)
                ->distinct()
                ->pluck('source_note_id'))
            ->map(fn ($noteId): string => (string) $noteId)
            ->all();
        $interactedNotes = array_fill_keys($interactedNoteIds, true);
        $hasMore = $limited->count() > $limit;
        $items = $limited->take($limit)->map(function (object $note) use ($interactedNotes): array {
            $canEdit = in_array($note->status, ['pending_review', 'published'], true)
                && now()->lessThan(Carbon::parse($note->created_at)->addMinutes(30))
                && ! isset($interactedNotes[(string) $note->id]);

            return [
                'id' => (string) $note->id,
                'content' => $note->content,
                'paper_color' => $note->paper_color,
                'status' => $note->status,
                'cell_x' => (int) $note->cell_x,
                'cell_y' => (int) $note->cell_y,
                'created_at' => $note->created_at,
                'allow_chat' => (bool) $note->allow_chat,
                'can_edit' => $canEdit,
                'can_delete' => $note->status !== 'deleted',
            ];
        })->values()->all();
        $last = $items === [] ? null : $items[array_key_last($items)];
        $cursor = $hasMore && $last !== null ? ['created_at' => $last['created_at'], 'id' => $last['id']] : null;

        return [
            'items' => $items,
            'next_cursor' => $cursor,
            'daily_quota_used' => DB::table('daily_note_creations')
                ->where('user_id', $actorId)
                ->where('creation_day_vn', now('Asia/Ho_Chi_Minh')->toDateString())
                ->exists(),
        ];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function editNote(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $requestId = $this->uuid($params, 'p_client_request_id');
        $content = $this->normalizeContent($params['p_new_content'] ?? null, 1000, 6144);
        $payloadHash = hash('sha256', json_encode(['note_id' => $noteId, 'content' => $content], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));

        return DB::transaction(function () use ($actorId, $noteId, $requestId, $content, $payloadHash): array {
            DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
            $previous = $this->idempotentResult($actorId, 'edit_note', $requestId, $payloadHash);
            if ($previous !== null) {
                return $previous;
            }

            $note = DB::table('notes')->where('id', $noteId)->where('author_id', $actorId)->lockForUpdate()->first();
            if ($note === null || ! in_array($note->status, ['pending_review', 'published'], true)) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            if (now()->greaterThanOrEqualTo(Carbon::parse($note->created_at)->addMinutes(30))) {
                throw new RpcError('EDIT_WINDOW_EXPIRED');
            }
            if (DB::table('encouragements')->where('note_id', $noteId)->exists()
                || DB::table('conversations')->where('source_note_id', $noteId)->exists()) {
                throw new RpcError('NOTE_ALREADY_INTERACTED');
            }

            $moderationMode = DB::table('app_settings')->where('setting_key', 'moderation_mode')->value('setting_value');
            $newStatus = $moderationMode === 'hold_all' || $this->contentHasContactInfo($content) ? 'pending_review' : 'published';
            $oldStatus = $note->status;
            DB::table('notes')->where('id', $noteId)->update([
                'content' => $content,
                'content_version' => DB::raw('content_version + 1'),
                'status' => $newStatus,
                'published_at' => $newStatus === 'published' ? ($note->published_at ?? now()) : null,
                'updated_at' => now(),
            ]);
            if ($newStatus === 'pending_review') {
                $reason = $moderationMode === 'hold_all' ? 'HOLD_ALL_EDIT' : 'CONTENT_EDIT';
                $this->enqueueNoteForModeration($noteId, $reason);
                $this->recordNoteModeration($noteId, $actorId, $oldStatus, $newStatus, $reason);
            } else {
                $this->resolveModerationQueue('note', $noteId);
            }
            if ($oldStatus === 'published' || $newStatus === 'published') {
                $this->syncPublishedRegion((int) $note->cell_x, (int) $note->cell_y);
            }
            $payload = [
                'id' => $noteId,
                'status' => $newStatus,
                'content' => $content,
                'content_version' => (int) $note->content_version + 1,
            ];
            $this->rememberIdempotentResult($actorId, 'edit_note', $requestId, $payloadHash, ['data' => $payload]);

            return $payload;
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function deleteNote(string $actorId, array $params): array
    {
        $noteId = $this->uuid($params, 'p_note_id');
        $requestId = $params['p_client_request_id'] ?? null;
        if ($requestId !== null && (! is_string($requestId) || ! Str::isUuid($requestId))) {
            throw new RpcError('INVALID_INPUT');
        }
        $payloadHash = hash('sha256', json_encode(['note_id' => $noteId], JSON_THROW_ON_ERROR));

        return DB::transaction(function () use ($actorId, $noteId, $requestId, $payloadHash): array {
            DB::table('users')->where('id', $actorId)->lockForUpdate()->first();
            if ($requestId !== null) {
                $previous = $this->idempotentResult($actorId, 'delete_note', $requestId, $payloadHash);
                if ($previous !== null) {
                    return $previous;
                }
            }

            $note = DB::table('notes')->where('id', $noteId)->where('author_id', $actorId)->lockForUpdate()->first();
            if ($note === null) {
                throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
            }
            if ($note->status !== 'deleted') {
                DB::table('notes')->where('id', $noteId)->update([
                    'status' => 'deleted', 'deleted_at' => now(), 'content' => '', 'allow_chat' => false, 'updated_at' => now(),
                ]);
                DB::table('active_note_cells')->where('note_id', $noteId)->delete();
                $this->recordNoteModeration($noteId, $actorId, $note->status, 'deleted', 'OWNER_DELETE');
                $this->resolveModerationQueue('note', $noteId);
                if ($note->status === 'published') {
                    $this->syncPublishedRegion((int) $note->cell_x, (int) $note->cell_y);
                }
            }
            $payload = ['deleted' => true];
            if ($requestId !== null) {
                $this->rememberIdempotentResult($actorId, 'delete_note', $requestId, $payloadHash, ['data' => $payload]);
            }

            return $payload;
        }, 3);
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function updateNoteChat(string $actorId, array $params): array
    {
        $this->requireEligible($actorId);
        $noteId = $this->uuid($params, 'p_note_id');
        $allowChat = $params['p_allow_chat'] ?? null;
        if (! is_bool($allowChat)) {
            throw new RpcError('INVALID_INPUT');
        }

        $matchingNote = DB::table('notes')->where('id', $noteId)->where('author_id', $actorId)
            ->whereIn('status', ['pending_review', 'published', 'hidden']);
        if (! $matchingNote->exists()) {
            throw new RpcError('NOTE_NOT_FOUND', '', false, 404);
        }
        $matchingNote->update(['allow_chat' => $allowChat, 'updated_at' => now()]);

        return ['allow_chat' => $allowChat];
    }

    private function requireEligible(string $actorId): void
    {
        if (! $this->accounts->isEligible($actorId)) {
            throw new RpcError('NOT_ELIGIBLE', 'Hoàn tất phần xác nhận tài khoản trước.', false, 403);
        }
    }

    private function floorDiv(int $value, int $divisor): int
    {
        return (int) floor($value / $divisor);
    }

    /** @param array<string, mixed> $params */
    private function integer(array $params, string $key): int
    {
        if (! array_key_exists($key, $params) || filter_var($params[$key], FILTER_VALIDATE_INT) === false) {
            throw new RpcError('INVALID_INPUT');
        }

        return (int) $params[$key];
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

    private function normalizeContent(mixed $value, int $maxCharacters, int $maxBytes): string
    {
        if (! is_string($value)) {
            throw new RpcError('INVALID_INPUT');
        }

        $normalized = trim(str_replace(["\r\n", "\r"], "\n", $value));
        if (class_exists(\Normalizer::class)) {
            $normalized = \Normalizer::normalize($normalized, \Normalizer::FORM_C) ?: $normalized;
        }

        if ($normalized === '' || mb_strlen($normalized) > $maxCharacters || strlen($normalized) > $maxBytes) {
            throw new RpcError('INVALID_INPUT', 'Hãy kiểm tra nội dung và lựa chọn của bạn.');
        }

        return $normalized;
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

    private function enqueueNoteForModeration(string $noteId, string $reason): void
    {
        DB::table('moderation_queue')->upsert([[
            'id' => (string) Str::uuid(),
            'target_type' => 'note',
            'target_id' => $noteId,
            'reason_code' => $reason,
            'queue_status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ]], ['target_type', 'target_id'], ['reason_code', 'queue_status', 'updated_at']);
    }

    private function resolveModerationQueue(string $targetType, string $targetId): void
    {
        DB::table('moderation_queue')->where('target_type', $targetType)->where('target_id', $targetId)
            ->whereIn('queue_status', ['pending', 'reviewing'])
            ->update(['queue_status' => 'resolved', 'updated_at' => now()]);
    }

    private function recordNoteModeration(string $noteId, ?string $actorId, ?string $from, string $to, string $reason): void
    {
        DB::table('moderation_events')->insert([
            'id' => (string) Str::uuid(),
            'note_id' => $noteId,
            'actor_id' => $actorId,
            'from_status' => $from,
            'to_status' => $to,
            'reason_code' => mb_substr($reason, 0, 100),
            'created_at' => now(),
        ]);
    }

    public function syncPublishedRegion(int $cellX, int $cellY): void
    {
        $tileX = $this->floorDiv($cellX, 8);
        $tileY = $this->floorDiv($cellY, 8);
        $count = DB::table('notes')->where('status', 'published')
            ->whereBetween('cell_x', [$tileX * 8, $tileX * 8 + 7])
            ->whereBetween('cell_y', [$tileY * 8, $tileY * 8 + 7])
            ->count();
        DB::table('app_counters')->where('counter_key', 'wall_revision')->increment('counter_value');
        $revision = (int) DB::table('app_counters')->where('counter_key', 'wall_revision')->value('counter_value');
        DB::table('wall_regions')->upsert([[
            'tile_x' => $tileX,
            'tile_y' => $tileY,
            'published_count' => $count,
            'revision' => $revision,
            'updated_at' => now(),
        ]], ['tile_x', 'tile_y'], ['published_count', 'revision', 'updated_at']);
        PrivateSignal::dispatch('wall:'.$tileX.':'.$tileY, 'wall_revision_changed');
    }
}
