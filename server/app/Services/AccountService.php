<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class AccountService
{
    public function ensureProfile(User $user): void
    {
        DB::table('profiles')->insertOrIgnore([
            'user_id' => $user->id,
            'account_status' => 'active',
            'reduced_motion' => false,
            'notifications_enabled' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function isEligible(string $userId): bool
    {
        $profile = DB::table('profiles')->where('user_id', $userId)->first();

        if ($profile === null || $profile->account_status !== 'active' || $profile->adult_confirmed_at === null) {
            return false;
        }

        foreach (['terms', 'privacy', 'community_rules', 'onboarding'] as $settingKey) {
            $profileColumn = $settingKey.'_version';
            $currentVersion = DB::table('app_settings')->where('setting_key', $settingKey.'_version')->value('setting_value');

            if ($currentVersion === null || $profile->{$profileColumn} !== $currentVersion) {
                return false;
            }
        }

        return true;
    }

    /** @return array<string, mixed> */
    public function settings(string $userId): array
    {
        $profile = DB::table('profiles')->where('user_id', $userId)->first();

        if ($profile === null) {
            return [
                'eligible' => false,
                'account_status' => 'active',
                'adult_confirmed' => false,
                'terms_version' => null,
                'privacy_version' => null,
                'community_rules_version' => null,
                'onboarding_version' => null,
                'is_moderator' => false,
                'reduced_motion' => false,
                'notifications_enabled' => false,
            ];
        }

        return [
            'eligible' => $this->isEligible($userId),
            'account_status' => $profile->account_status,
            'adult_confirmed' => $profile->adult_confirmed_at !== null,
            'terms_version' => $profile->terms_version,
            'privacy_version' => $profile->privacy_version,
            'community_rules_version' => $profile->community_rules_version,
            'onboarding_version' => $profile->onboarding_version,
            'is_moderator' => DB::table('admin_roles')->where('user_id', $userId)->exists(),
            'reduced_motion' => (bool) $profile->reduced_motion,
            'notifications_enabled' => (bool) $profile->notifications_enabled,
        ];
    }

    public function isModerator(string $userId): bool
    {
        return DB::table('admin_roles')->where('user_id', $userId)->exists();
    }

    public function recordConsent(string $userId, string $kind, string $version): void
    {
        DB::table('user_consents')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'user_id' => $userId,
            'consent_kind' => $kind,
            'policy_version' => $version,
            'accepted_at' => now(),
            'accepted' => true,
        ]);
    }
}
