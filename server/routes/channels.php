<?php

use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\DB;

Broadcast::channel('user:{userId}', function ($user, string $userId): bool {
    return (string) $user->id === $userId;
});

Broadcast::channel('conversation:{conversationId}', function ($user, string $conversationId): bool {
    return DB::table('conversations')
        ->where('id', $conversationId)
        ->where('status', 'active')
        ->where(function ($query) use ($user): void {
            $query->where('participant_low', $user->id)
                ->orWhere('participant_high', $user->id);
        })
        ->exists();
});

Broadcast::channel('wall:{tileX}:{tileY}', function ($user, string $tileX, string $tileY): bool {
    if (! preg_match('/^-?\d+$/', $tileX) || ! preg_match('/^-?\d+$/', $tileY)) {
        return false;
    }

    $profile = DB::table('profiles')->where('user_id', $user->id)->first();

    return $profile !== null
        && $profile->account_status === 'active'
        && $profile->adult_confirmed_at !== null
        && $profile->terms_version === DB::table('app_settings')->where('setting_key', 'terms_version')->value('setting_value')
        && $profile->privacy_version === DB::table('app_settings')->where('setting_key', 'privacy_version')->value('setting_value')
        && $profile->community_rules_version === DB::table('app_settings')->where('setting_key', 'community_rules_version')->value('setting_value')
        && $profile->onboarding_version === DB::table('app_settings')->where('setting_key', 'onboarding_version')->value('setting_value');
});
