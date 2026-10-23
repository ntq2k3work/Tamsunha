<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\RpcController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::post('/auth/request-code', [AuthController::class, 'requestCode'])
        ->middleware('throttle:email-code');
    Route::post('/auth/verify-code', [AuthController::class, 'verifyCode'])
        ->middleware('throttle:email-verify');
    Route::post('/auth/logout', [AuthController::class, 'logout'])
        ->middleware('auth:sanctum');

    Route::post('/rpc/{operation}', [RpcController::class, 'dispatch'])
        ->middleware('auth:sanctum')
        ->where('operation', '[a-z_]+');
});
