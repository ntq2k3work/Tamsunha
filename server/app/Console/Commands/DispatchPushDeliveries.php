<?php

namespace App\Console\Commands;

use App\Services\FirebaseMessagingClient;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

#[Signature('push:dispatch {--limit=50 : Maximum number of queued deliveries to claim (1-100)}')]
#[Description('Send queued neutral notifications through Firebase Cloud Messaging')]
class DispatchPushDeliveries extends Command
{
    public function handle(FirebaseMessagingClient $firebase): int
    {
        if (! $firebase->isConfigured()) {
            $this->warn('Push dispatch skipped: Firebase service credentials are not configured.');

            return self::SUCCESS;
        }

        $limitOption = $this->option('limit');
        if (! is_string($limitOption) || ! ctype_digit($limitOption)) {
            $this->error('The limit must be an integer between 1 and 100.');

            return self::INVALID;
        }
        $limit = max(1, min(100, (int) $limitOption));
        $deliveries = $this->claimDeliveries($limit);
        $counts = ['sent' => 0, 'invalid_token' => 0, 'retried' => 0, 'failed' => 0];

        foreach ($deliveries as $delivery) {
            try {
                $result = $firebase->send((string) $delivery->push_token, (string) $delivery->notification_type);
            } catch (Throwable $exception) {
                Log::warning('Push provider request failed.', ['exception' => $exception::class]);
                $result = ['outcome' => 'retry', 'error_code' => 'UNKNOWN'];
            }

            try {
                $updated = $this->completeDelivery((string) $delivery->id, (string) $delivery->device_id, $result);
            } catch (QueryException $exception) {
                Log::error('Push delivery state could not be updated.', ['exception' => $exception::class]);
                $counts['failed']++;

                continue;
            }
            if (! $updated) {
                $counts['failed']++;
            } elseif ($result['outcome'] === 'sent') {
                $counts['sent']++;
            } elseif ($result['outcome'] === 'invalid_token') {
                $counts['invalid_token']++;
            } else {
                $counts['retried']++;
            }
        }

        $this->info(sprintf(
            'Claimed %d; sent %d; removed invalid tokens %d; retried %d; state errors %d.',
            count($deliveries), $counts['sent'], $counts['invalid_token'], $counts['retried'], $counts['failed'],
        ));

        return self::SUCCESS;
    }

    /** @return list<object> */
    private function claimDeliveries(int $limit): array
    {
        return DB::transaction(function () use ($limit): array {
            $now = now();
            $rows = DB::table('push_delivery_outbox as outbox')
                ->join('notifications', 'notifications.id', '=', 'outbox.notification_id')
                ->join('user_devices as device', 'device.id', '=', 'outbox.device_id')
                ->join('profiles as profile', 'profile.user_id', '=', 'notifications.recipient_id')
                ->whereIn('outbox.status', ['pending', 'sending'])
                ->where('outbox.attempt_count', '<', 8)
                ->where('outbox.available_at', '<=', $now)
                ->where(function ($lease) use ($now): void {
                    $lease->whereNull('outbox.locked_until')->orWhere('outbox.locked_until', '<', $now);
                })
                ->where('profile.notifications_enabled', true)
                ->where('profile.account_status', 'active')
                ->orderBy('outbox.available_at')->orderBy('outbox.created_at')->orderBy('outbox.id')
                ->limit($limit)
                ->lock('for update skip locked')
                ->get([
                    'outbox.id', 'outbox.notification_id', 'outbox.device_id', 'outbox.attempt_count',
                    'notifications.notification_type', 'device.push_token',
                ]);

            foreach ($rows as $row) {
                DB::table('push_delivery_outbox')->where('id', $row->id)->update([
                    'status' => 'sending',
                    'attempt_count' => (int) $row->attempt_count + 1,
                    'locked_until' => $now->copy()->addMinutes(2),
                ]);
                $row->attempt_count = (int) $row->attempt_count + 1;
            }

            return $rows->all();
        }, 3);
    }

    /** @param array{outcome: string, error_code: string} $result */
    private function completeDelivery(string $deliveryId, string $deviceId, array $result): bool
    {
        return DB::transaction(function () use ($deliveryId, $deviceId, $result): bool {
            $delivery = DB::table('push_delivery_outbox')->where('id', $deliveryId)->lockForUpdate()->first();
            if ($delivery === null) {
                return false;
            }
            $errorCode = in_array($result['error_code'], ['UNREGISTERED', 'INVALID_ARGUMENT', 'UNAVAILABLE', 'INTERNAL'], true)
                ? $result['error_code']
                : 'UNKNOWN';

            if ($result['outcome'] === 'invalid_token') {
                DB::table('user_devices')->where('id', $deviceId)->delete();

                return true;
            }
            if ($result['outcome'] === 'sent') {
                DB::table('push_delivery_outbox')->where('id', $deliveryId)->update([
                    'status' => 'sent',
                    'sent_at' => now(),
                    'locked_until' => null,
                    'last_error_code' => null,
                ]);

                return true;
            }
            if ((int) $delivery->attempt_count >= 8) {
                DB::table('push_delivery_outbox')->where('id', $deliveryId)->update([
                    'status' => 'failed',
                    'locked_until' => null,
                    'last_error_code' => $errorCode,
                ]);

                return true;
            }

            $delaySeconds = min(3600, 15 * (2 ** (int) $delivery->attempt_count));
            DB::table('push_delivery_outbox')->where('id', $deliveryId)->update([
                'status' => 'pending',
                'available_at' => now()->addSeconds($delaySeconds),
                'locked_until' => null,
                'last_error_code' => $errorCode,
            ]);

            return true;
        }, 3);
    }
}
