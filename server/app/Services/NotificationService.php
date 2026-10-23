<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class NotificationService
{
    public function create(string $recipientId, string $type, string $sourceId, ?string $conversationId = null): void
    {
        $now = now();
        DB::table('notifications')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'recipient_id' => $recipientId,
            'notification_type' => $type,
            'source_id' => $sourceId,
            'conversation_id' => $conversationId,
            'created_at' => $now,
            'read_at' => null,
        ]);

        $notificationId = DB::table('notifications')
            ->where('recipient_id', $recipientId)
            ->where('notification_type', $type)
            ->where('source_id', $sourceId)
            ->value('id');

        if ($notificationId === null || ! DB::table('profiles')->where('user_id', $recipientId)->where('notifications_enabled', true)->exists()) {
            return;
        }

        $devices = DB::table('user_devices')->where('user_id', $recipientId)->get(['id']);
        foreach ($devices as $device) {
            DB::table('push_delivery_outbox')->insertOrIgnore([
                'id' => (string) Str::uuid(),
                'notification_id' => $notificationId,
                'device_id' => $device->id,
                'status' => 'pending',
                'attempt_count' => 0,
                'available_at' => $now,
                'created_at' => $now,
            ]);
        }
    }
}
