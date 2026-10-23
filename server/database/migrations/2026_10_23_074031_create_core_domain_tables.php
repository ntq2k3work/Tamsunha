<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('app_settings', function (Blueprint $table): void {
            $table->string('setting_key', 100)->primary();
            $table->text('setting_value');
            $table->timestamp('updated_at')->useCurrent();
        });

        DB::table('app_settings')->insert([
            ['setting_key' => 'terms_version', 'setting_value' => 'terms-v1'],
            ['setting_key' => 'privacy_version', 'setting_value' => 'privacy-v1'],
            ['setting_key' => 'community_rules_version', 'setting_value' => 'community-v1'],
            ['setting_key' => 'onboarding_version', 'setting_value' => 'onboarding-v1'],
            ['setting_key' => 'moderation_mode', 'setting_value' => 'hold_all'],
        ]);

        Schema::create('app_counters', function (Blueprint $table): void {
            $table->string('counter_key', 80)->primary();
            $table->unsignedBigInteger('counter_value')->default(0);
        });
        DB::table('app_counters')->insert([
            'counter_key' => 'wall_revision',
            'counter_value' => 0,
        ]);

        Schema::create('profiles', function (Blueprint $table): void {
            $table->foreignUuid('user_id')->primary()->constrained('users')->cascadeOnDelete();
            $table->string('account_status', 32)->default('active')->index();
            $table->timestamp('adult_confirmed_at')->nullable();
            $table->string('terms_version', 64)->nullable();
            $table->string('privacy_version', 64)->nullable();
            $table->string('community_rules_version', 64)->nullable();
            $table->string('onboarding_version', 64)->nullable();
            $table->boolean('reduced_motion')->default(false);
            $table->boolean('notifications_enabled')->default(false);
            $table->timestamps();
        });

        Schema::create('user_consents', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('consent_kind', 32);
            $table->string('policy_version', 64);
            $table->timestamp('accepted_at')->useCurrent();
            $table->boolean('accepted');
            $table->unique(['user_id', 'consent_kind', 'policy_version'], 'user_consents_unique');
            $table->index(['user_id', 'accepted_at'], 'user_consents_user_time_idx');
        });

        Schema::create('notes', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('author_id')->constrained('users')->restrictOnDelete();
            $table->text('content');
            $table->string('paper_color', 16);
            $table->integer('style_seed');
            $table->bigInteger('cell_x');
            $table->bigInteger('cell_y');
            $table->boolean('allow_chat')->default(true);
            $table->string('status', 24)->default('pending_review');
            $table->timestamp('published_at')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->unsignedInteger('content_version')->default(1);
            $table->timestamps();
            $table->index(['status', 'cell_y', 'cell_x', 'id'], 'notes_published_cell_idx');
            $table->index(['author_id', 'created_at', 'id'], 'notes_owner_created_idx');
            $table->index(['author_id', 'status', 'created_at'], 'notes_owner_active_idx');
        });

        Schema::create('active_note_cells', function (Blueprint $table): void {
            $table->bigInteger('cell_x');
            $table->bigInteger('cell_y');
            $table->uuid('note_id')->unique();
            $table->primary(['cell_x', 'cell_y']);
            $table->foreign('note_id')->references('id')->on('notes')->cascadeOnDelete();
        });

        Schema::create('daily_note_creations', function (Blueprint $table): void {
            $table->foreignUuid('user_id')->constrained('users')->restrictOnDelete();
            $table->date('creation_day_vn');
            $table->uuid('note_id')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->primary(['user_id', 'creation_day_vn']);
            $table->foreign('note_id')->references('id')->on('notes')->nullOnDelete();
        });

        Schema::create('wall_regions', function (Blueprint $table): void {
            $table->bigInteger('tile_x');
            $table->bigInteger('tile_y');
            $table->unsignedInteger('published_count')->default(0);
            $table->unsignedBigInteger('revision')->default(0);
            $table->timestamp('updated_at')->useCurrent();
            $table->primary(['tile_x', 'tile_y']);
        });

        Schema::create('request_idempotency', function (Blueprint $table): void {
            $table->foreignUuid('actor_id')->constrained('users')->cascadeOnDelete();
            $table->string('operation', 80);
            $table->uuid('request_id');
            $table->char('payload_hash', 64);
            $table->json('result');
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('expires_at');
            $table->primary(['actor_id', 'operation', 'request_id'], 'request_idempotency_pk');
            $table->index('expires_at');
        });

        Schema::create('moderation_events', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('note_id')->nullable()->constrained('notes')->nullOnDelete();
            $table->foreignUuid('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('from_status', 24)->nullable();
            $table->string('to_status', 24);
            $table->string('reason_code', 100);
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('admin_roles', function (Blueprint $table): void {
            $table->foreignUuid('user_id')->primary()->constrained('users')->cascadeOnDelete();
            $table->string('role', 24);
            $table->foreignUuid('granted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('granted_at')->useCurrent();
        });

        Schema::create('admin_audit_logs', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 100);
            $table->string('target_type', 32);
            $table->uuid('target_id')->nullable();
            $table->string('reason', 500);
            $table->timestamp('created_at')->useCurrent();
            $table->index(['created_at', 'id']);
        });

        Schema::create('login_challenges', function (Blueprint $table): void {
            $table->char('email_hash', 64)->primary();
            $table->char('code_hash', 64);
            $table->unsignedTinyInteger('attempt_count')->default(0);
            $table->timestamp('requested_at');
            $table->timestamp('expires_at')->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('login_challenges');
        Schema::dropIfExists('admin_audit_logs');
        Schema::dropIfExists('admin_roles');
        Schema::dropIfExists('moderation_events');
        Schema::dropIfExists('request_idempotency');
        Schema::dropIfExists('wall_regions');
        Schema::dropIfExists('daily_note_creations');
        Schema::dropIfExists('active_note_cells');
        Schema::dropIfExists('notes');
        Schema::dropIfExists('user_consents');
        Schema::dropIfExists('profiles');
        Schema::dropIfExists('app_counters');
        Schema::dropIfExists('app_settings');
    }
};
