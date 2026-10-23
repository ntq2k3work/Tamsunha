<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        RateLimiter::for('email-code', function (Request $request): Limit {
            return Limit::perMinute(10)->by($request->ip() ?? 'unknown');
        });

        RateLimiter::for('email-verify', function (Request $request): Limit {
            return Limit::perMinute(20)->by($request->ip() ?? 'unknown');
        });
    }
}
