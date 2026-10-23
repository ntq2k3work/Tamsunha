<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\AccountService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Validator;
use Laravel\Sanctum\PersonalAccessToken;
use Throwable;

class AuthController extends Controller
{
    public function requestCode(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'email' => ['required', 'string', 'email:rfc', 'max:254'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'error' => [
                    'code' => 'INVALID_INPUT',
                    'message' => 'Hãy nhập một địa chỉ email hợp lệ.',
                ],
            ], 422);
        }

        $email = mb_strtolower(trim((string) $request->string('email')));
        $emailHash = hash_hmac('sha256', $email, (string) config('app.key'));
        $rateLimitKey = 'login-code:'.$emailHash;

        if (RateLimiter::tooManyAttempts($rateLimitKey, 3)) {
            return response()->json([
                'error' => [
                    'code' => 'OTP_RATE_LIMITED',
                    'message' => 'Bạn vừa yêu cầu mã. Hãy chờ một chút rồi thử lại.',
                    'retryable' => true,
                ],
            ], 429);
        }

        RateLimiter::hit($rateLimitKey, 60);
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $codeHash = hash_hmac('sha256', $email.'|'.$code, (string) config('app.key'));
        $requestedAt = now();

        DB::table('login_challenges')->upsert(
            [[
                'email_hash' => $emailHash,
                'code_hash' => $codeHash,
                'attempt_count' => 0,
                'requested_at' => $requestedAt,
                'expires_at' => $requestedAt->copy()->addMinutes(10),
            ]],
            ['email_hash'],
            ['code_hash', 'attempt_count', 'requested_at', 'expires_at'],
        );

        try {
            Mail::raw('Mã đăng nhập Tường Nhỏ của bạn là '.$code.'. Mã có hiệu lực trong 10 phút.', function ($message) use ($email): void {
                $message->to($email)->subject('Mã đăng nhập Tường Nhỏ');
            });
        } catch (Throwable) {
            return response()->json([
                'error' => [
                    'code' => 'SERVICE_UNAVAILABLE',
                    'message' => 'Chưa gửi được mã xác nhận. Hãy thử lại sau.',
                    'retryable' => true,
                ],
            ], 503);
        }

        return response()->json([
            'data' => [
                'sent' => true,
                'message' => 'Nếu địa chỉ email hợp lệ, mã xác nhận đã được gửi.',
            ],
        ]);
    }

    public function verifyCode(Request $request, AccountService $accountService): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'email' => ['required', 'string', 'email:rfc', 'max:254'],
            'code' => ['required', 'regex:/^\d{6}$/'],
            'device_name' => ['nullable', 'string', 'max:80'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'error' => [
                    'code' => 'INVALID_INPUT',
                    'message' => 'Hãy kiểm tra lại email và mã 6 chữ số.',
                ],
            ], 422);
        }

        $email = mb_strtolower(trim((string) $request->string('email')));
        $code = (string) $request->string('code');
        $emailHash = hash_hmac('sha256', $email, (string) config('app.key'));
        $expectedCodeHash = hash_hmac('sha256', $email.'|'.$code, (string) config('app.key'));
        $deviceName = trim((string) ($request->input('device_name') ?: 'Tường Nhỏ'));

        $result = DB::transaction(function () use ($email, $emailHash, $expectedCodeHash, $deviceName): array {
            $challenge = DB::table('login_challenges')
                ->where('email_hash', $emailHash)
                ->lockForUpdate()
                ->first();

            if ($challenge === null || CarbonImmutable::parse($challenge->expires_at)->isPast() || $challenge->attempt_count >= 5) {
                return ['error' => 'OTP_INVALID_OR_EXPIRED'];
            }

            if (! hash_equals($challenge->code_hash, $expectedCodeHash)) {
                DB::table('login_challenges')->where('email_hash', $emailHash)->increment('attempt_count');

                return ['error' => 'OTP_INVALID_OR_EXPIRED'];
            }

            DB::table('login_challenges')->where('email_hash', $emailHash)->delete();

            $user = User::query()->where('email', $email)->lockForUpdate()->first();

            if ($user === null) {
                $user = User::query()->create([
                    'email' => $email,
                ]);
            }

            if ($user->email_verified_at === null) {
                $user->forceFill(['email_verified_at' => now()])->save();
            }

            $accountService->ensureProfile($user);
            $token = $user->createToken(
                $deviceName,
                ['*'],
                now()->addDays((int) config('tamsunha.api_token_ttl_days', 30)),
            );

            return [
                'token' => $token->plainTextToken,
                'user' => [
                    'id' => (string) $user->id,
                    'email' => $user->email,
                ],
                'settings' => $accountService->settings((string) $user->id),
            ];
        }, 3);

        if (isset($result['error'])) {
            return response()->json([
                'error' => [
                    'code' => 'OTP_INVALID_OR_EXPIRED',
                    'message' => 'Mã xác nhận không đúng hoặc đã hết hạn.',
                ],
            ], 422);
        }

        return response()->json(['data' => $result]);
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()?->currentAccessToken();

        if ($token instanceof PersonalAccessToken) {
            $token->delete();
        }

        return response()->json(['data' => ['signed_out' => true]]);
    }
}
