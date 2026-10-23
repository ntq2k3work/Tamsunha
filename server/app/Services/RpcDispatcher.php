<?php

namespace App\Services;

use App\Exceptions\RpcError;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final class RpcDispatcher
{
    public function __construct(
        private readonly AccountService $accounts,
        private readonly WallOperations $wall,
        private readonly EngagementOperations $engagement,
        private readonly SafetyOperations $safety,
        private readonly ModerationOperations $moderation,
    ) {}

    /** @param array<string, mixed> $params
     * @return array{data: array<string, mixed>}
     */
    public function dispatch(User $actor, string $operation, array $params): array
    {
        $actorId = (string) $actor->id;

        $payload = match ($operation) {
            'get_account_settings' => $this->accounts->settings($actorId),
            'complete_onboarding' => $this->completeOnboarding($actorId, $params),
            'update_settings' => $this->updateSettings($actorId, $params),
            'request_account_deletion' => $this->safety->requestAccountDeletion($actorId, $params),
            'get_wall_tiles' => $this->wall->getWallTiles($actorId, $params),
            'get_wall_density' => $this->wall->getWallDensity($actorId, $params),
            'get_note_detail' => $this->wall->getNoteDetail($actorId, $params),
            'get_discovery_target' => $this->wall->getDiscoveryTarget($actorId, $params),
            'suggest_placement_regions' => $this->wall->suggestPlacementRegions($actorId, $params),
            'place_note' => $this->wall->placeNote($actorId, $params),
            'get_my_notes' => $this->wall->getMyNotes($actorId, $params),
            'edit_note' => $this->wall->editNote($actorId, $params),
            'delete_note' => $this->wall->deleteNote($actorId, $params),
            'update_note_chat' => $this->wall->updateNoteChat($actorId, $params),
            'send_encouragement' => $this->engagement->sendEncouragement($actorId, $params),
            'start_conversation_from_note' => $this->engagement->startConversation($actorId, $params),
            'send_message' => $this->engagement->sendMessage($actorId, $params),
            'get_messages' => $this->engagement->getMessages($actorId, $params),
            'get_inbox' => $this->engagement->getInbox($actorId, $params),
            'close_conversation' => $this->engagement->closeConversation($actorId, $params),
            'mark_notification_read' => $this->safety->markNotificationRead($actorId, $params),
            'block_from_note' => $this->safety->blockFromNote($actorId, $params),
            'block_from_conversation' => $this->safety->blockFromConversation($actorId, $params),
            'get_my_blocks' => $this->safety->getMyBlocks($actorId),
            'unblock_from_my_list' => $this->safety->unblockFromMyList($actorId, $params),
            'report_content' => $this->safety->reportContent($actorId, $params),
            'report_user_from_note' => $this->safety->reportUserFromNote($actorId, $params),
            'report_user_from_conversation' => $this->safety->reportUserFromConversation($actorId, $params),
            'report_and_block_user_from_note' => $this->safety->reportAndBlockUserFromNote($actorId, $params),
            'report_and_block_user_from_conversation' => $this->safety->reportAndBlockUserFromConversation($actorId, $params),
            'report_and_block_note' => $this->safety->reportAndBlockNote($actorId, $params),
            'report_and_block_conversation' => $this->safety->reportAndBlockConversation($actorId, $params),
            'report_and_block_message' => $this->safety->reportAndBlockMessage($actorId, $params),
            'register_device' => $this->safety->registerDevice($actorId, $params),
            'unregister_device' => $this->safety->unregisterDevice($actorId, $params),
            'get_moderation_queue' => $this->moderation->getModerationQueue($actorId, $params),
            'get_reports_queue' => $this->moderation->getReportsQueue($actorId, $params),
            'get_deletion_queue' => $this->moderation->getDeletionQueue($actorId, $params),
            'moderate_note' => $this->moderation->moderateNote($actorId, $params),
            'moderate_message' => $this->moderation->moderateMessage($actorId, $params),
            'review_report' => $this->moderation->reviewReport($actorId, $params),
            'process_deletion_request' => $this->moderation->processDeletionRequest($actorId, $params),
            'moderate_account' => $this->moderation->moderateAccount($actorId, $params),
            default => throw new RpcError('NOT_FOUND', 'Thao tác này không tồn tại.', false, 404),
        };

        return ['data' => $payload];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    private function completeOnboarding(string $actorId, array $params): array
    {
        $required = [
            'p_age_confirmed', 'p_terms_accepted', 'p_privacy_accepted',
            'p_community_rules_accepted', 'p_onboarding_acknowledged',
            'p_terms_version', 'p_privacy_version', 'p_community_rules_version', 'p_onboarding_version',
        ];

        foreach ($required as $key) {
            if (! array_key_exists($key, $params)) {
                throw new RpcError('INVALID_INPUT');
            }
        }

        if ($params['p_age_confirmed'] !== true) {
            throw new RpcError('AGE_RESTRICTED', 'Bạn cần xác nhận đã đủ 18 tuổi.');
        }

        foreach (['p_terms_accepted', 'p_privacy_accepted', 'p_community_rules_accepted', 'p_onboarding_acknowledged'] as $key) {
            if ($params[$key] !== true) {
                throw new RpcError('CONSENT_REQUIRED');
            }
        }

        $versions = [
            'terms' => DB::table('app_settings')->where('setting_key', 'terms_version')->value('setting_value'),
            'privacy' => DB::table('app_settings')->where('setting_key', 'privacy_version')->value('setting_value'),
            'community_rules' => DB::table('app_settings')->where('setting_key', 'community_rules_version')->value('setting_value'),
            'onboarding' => DB::table('app_settings')->where('setting_key', 'onboarding_version')->value('setting_value'),
        ];

        if ($params['p_terms_version'] !== $versions['terms']
            || $params['p_privacy_version'] !== $versions['privacy']
            || $params['p_community_rules_version'] !== $versions['community_rules']
            || $params['p_onboarding_version'] !== $versions['onboarding']) {
            throw new RpcError('POLICY_VERSION_MISMATCH');
        }

        DB::transaction(function () use ($actorId, $versions): void {
            $profile = DB::table('profiles')->where('user_id', $actorId)->lockForUpdate()->first();

            if ($profile === null || $profile->account_status !== 'active') {
                throw new RpcError('SUSPENDED', '', false, 403);
            }

            DB::table('profiles')->where('user_id', $actorId)->update([
                'adult_confirmed_at' => $profile->adult_confirmed_at ?? now(),
                'terms_version' => $versions['terms'],
                'privacy_version' => $versions['privacy'],
                'community_rules_version' => $versions['community_rules'],
                'onboarding_version' => $versions['onboarding'],
                'updated_at' => now(),
            ]);

            $this->accounts->recordConsent($actorId, 'adult_18_plus', 'self-declared-v1');
            foreach ($versions as $kind => $version) {
                $this->accounts->recordConsent($actorId, $kind, $version);
            }
        });

        return ['eligible' => true];
    }

    /** @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    private function updateSettings(string $actorId, array $params): array
    {
        if (! $this->accounts->isEligible($actorId)) {
            throw new RpcError('NOT_ELIGIBLE', 'Hoàn tất phần xác nhận tài khoản trước.');
        }

        $reducedMotion = $params['p_reduced_motion'] ?? null;
        $notificationsEnabled = $params['p_notifications_enabled'] ?? null;

        if (($reducedMotion !== null && ! is_bool($reducedMotion))
            || ($notificationsEnabled !== null && ! is_bool($notificationsEnabled))
            || ($reducedMotion === null && $notificationsEnabled === null)) {
            throw new RpcError('INVALID_INPUT');
        }

        $changes = ['updated_at' => now()];
        if ($reducedMotion !== null) {
            $changes['reduced_motion'] = $reducedMotion;
        }
        if ($notificationsEnabled !== null) {
            $changes['notifications_enabled'] = $notificationsEnabled;
        }

        DB::transaction(function () use ($actorId, $changes, $notificationsEnabled): void {
            DB::table('profiles')->where('user_id', $actorId)->update($changes);
            if ($notificationsEnabled === false) {
                DB::table('user_devices')->where('user_id', $actorId)->delete();
            }
        });

        $settings = DB::table('profiles')->where('user_id', $actorId)->first();

        return [
            'reduced_motion' => (bool) $settings->reduced_motion,
            'notifications_enabled' => (bool) $settings->notifications_enabled,
        ];
    }
}
