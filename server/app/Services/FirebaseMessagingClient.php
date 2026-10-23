<?php

namespace App\Services;

use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use RuntimeException;

final class FirebaseMessagingClient
{
    /** @return array{outcome: 'sent'|'invalid_token'|'retry', error_code: string} */
    public function send(string $pushToken, string $notificationType): array
    {
        $account = $this->serviceAccount();
        $accessToken = $this->accessToken($account);
        $encouragement = $notificationType === 'encouragement';
        $collapseKey = $encouragement ? 'tn_encouragement' : 'tn_message';
        $expiresAt = time() + 86_400;
        $message = [
            'message' => [
                'token' => $pushToken,
                'notification' => [
                    'title' => 'Tường Nhỏ',
                    'body' => $encouragement
                        ? 'Bạn vừa nhận được một lời động viên trong Tường Nhỏ.'
                        : 'Bạn có một lời nhắn mới trong Tường Nhỏ.',
                ],
                'data' => [
                    'event_type' => $encouragement ? 'encouragement_received' : 'new_message',
                    'route' => '/inbox',
                ],
                'android' => [
                    'priority' => 'normal',
                    'ttl' => '86400s',
                    'collapse_key' => $collapseKey,
                    'notification' => ['tag' => $collapseKey],
                ],
                'apns' => [
                    'headers' => [
                        'apns-push-type' => 'alert',
                        'apns-priority' => '5',
                        'apns-expiration' => (string) $expiresAt,
                        'apns-collapse-id' => $collapseKey,
                    ],
                    'payload' => ['aps' => ['sound' => 'default']],
                ],
            ],
        ];

        $response = Http::withToken($accessToken)
            ->acceptJson()
            ->timeout(15)
            ->post('https://fcm.googleapis.com/v1/projects/'.rawurlencode($account['project_id']).'/messages:send', $message);

        if ($response->successful()) {
            return ['outcome' => 'sent', 'error_code' => 'UNKNOWN'];
        }

        $errorCode = $this->firebaseErrorCode($response);

        return [
            'outcome' => $errorCode === 'UNREGISTERED' ? 'invalid_token' : 'retry',
            'error_code' => $errorCode,
        ];
    }

    public function isConfigured(): bool
    {
        try {
            $this->serviceAccount();

            return true;
        } catch (RuntimeException) {
            return false;
        }
    }

    /** @return array{client_email: string, private_key: string, project_id: string} */
    private function serviceAccount(): array
    {
        $raw = config('services.firebase.service_account_json');
        if (! is_string($raw) || trim($raw) === '') {
            throw new RuntimeException('FIREBASE_PROVIDER_UNAVAILABLE');
        }

        try {
            $account = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            throw new RuntimeException('FIREBASE_PROVIDER_UNAVAILABLE', previous: $exception);
        }
        if (! is_array($account)
            || ! is_string($account['client_email'] ?? null)
            || ! is_string($account['private_key'] ?? null)
            || ! is_string($account['project_id'] ?? null)
            || $account['client_email'] === ''
            || $account['private_key'] === ''
            || $account['project_id'] === '') {
            throw new RuntimeException('FIREBASE_PROVIDER_UNAVAILABLE');
        }

        return [
            'client_email' => $account['client_email'],
            'private_key' => str_replace('\\n', "\n", $account['private_key']),
            'project_id' => $account['project_id'],
        ];
    }

    /** @param array{client_email: string, private_key: string, project_id: string} $account */
    private function accessToken(array $account): string
    {
        $cacheKey = 'firebase-messaging-token:'.hash('sha256', $account['client_email'].'|'.$account['project_id']);
        $cachedToken = Cache::get($cacheKey);
        if (is_string($cachedToken) && $cachedToken !== '') {
            return $cachedToken;
        }

        $issuedAt = time();
        $unsignedJwt = $this->base64Url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR)).'.'
            .$this->base64Url(json_encode([
                'iss' => $account['client_email'],
                'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                'aud' => 'https://oauth2.googleapis.com/token',
                'iat' => $issuedAt,
                'exp' => $issuedAt + 3600,
            ], JSON_THROW_ON_ERROR));
        $privateKey = openssl_pkey_get_private($account['private_key']);
        if ($privateKey === false || ! openssl_sign($unsignedJwt, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('FIREBASE_AUTH_UNAVAILABLE');
        }
        $assertion = $unsignedJwt.'.'.$this->base64Url($signature);
        $response = Http::asForm()->acceptJson()->timeout(10)->post('https://oauth2.googleapis.com/token', [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $assertion,
        ]);
        $body = $response->json();
        if (! $response->successful() || ! is_array($body)
            || ! is_string($body['access_token'] ?? null)
            || ! is_numeric($body['expires_in'] ?? null)) {
            throw new RuntimeException('FIREBASE_AUTH_UNAVAILABLE');
        }

        Cache::put($cacheKey, $body['access_token'], max(60, (int) $body['expires_in'] - 60));

        return $body['access_token'];
    }

    private function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private function firebaseErrorCode(Response $response): string
    {
        $body = $response->json();
        $error = is_array($body) && is_array($body['error'] ?? null) ? $body['error'] : [];
        $details = is_array($error['details'] ?? null) ? $error['details'] : [];
        foreach ($details as $detail) {
            if (! is_array($detail)) {
                continue;
            }
            $code = $detail['errorCode'] ?? null;
            if (in_array($code, ['UNREGISTERED', 'INVALID_ARGUMENT'], true)) {
                return $code;
            }
        }

        $status = $error['status'] ?? null;

        return in_array($status, ['UNAVAILABLE', 'INTERNAL'], true) ? $status : 'UNKNOWN';
    }
}
