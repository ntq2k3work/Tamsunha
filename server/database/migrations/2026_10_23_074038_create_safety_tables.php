<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('blocks', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('blocker_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('blocked_id')->constrained('users')->restrictOnDelete();
            $table->foreignUuid('source_note_id')->nullable()->constrained('notes')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['blocker_id', 'blocked_id']);
            $table->index('blocked_id');
        });

        Schema::create('reports', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('reporter_id')->constrained('users')->restrictOnDelete();
            $table->string('target_type', 24);
            $table->uuid('target_id');
            $table->string('reason', 32);
            $table->text('description')->nullable();
            $table->string('status', 24)->default('pending');
            $table->foreignUuid('moderator_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();
            $table->unique(['reporter_id', 'target_type', 'target_id'], 'reports_reporter_target_unique');
            $table->index(['status', 'created_at', 'id'], 'reports_queue_idx');
            $table->index(['reporter_id', 'created_at', 'id'], 'reports_reporter_idx');
        });

        Schema::create('account_deletion_requests', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->restrictOnDelete();
            $table->string('status', 24)->default('pending');
            $table->timestamp('requested_at')->useCurrent();
            $table->timestamps();
            $table->string('resolution_code', 100)->nullable();
            $table->unique('user_id');
        });

        Schema::create('user_devices', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('device_key_hash', 128);
            $table->text('push_token');
            $table->string('platform', 16);
            $table->timestamps();
            $table->unique(['user_id', 'device_key_hash'], 'user_devices_user_key_unique');
            $table->index('user_id');
        });

        Schema::create('moderation_queue', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->string('target_type', 24);
            $table->uuid('target_id');
            $table->string('reason_code', 100);
            $table->string('queue_status', 24)->default('pending');
            $table->timestamps();
            $table->unique(['target_type', 'target_id']);
            $table->index(['queue_status', 'created_at', 'id'], 'moderation_queue_pending_idx');
        });

        Schema::create('message_moderation_events', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('message_id')->nullable()->constrained('messages')->nullOnDelete();
            $table->foreignUuid('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reason_code', 100);
            $table->timestamp('created_at')->useCurrent();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('message_moderation_events');
        Schema::dropIfExists('moderation_queue');
        Schema::dropIfExists('user_devices');
        Schema::dropIfExists('account_deletion_requests');
        Schema::dropIfExists('reports');
        Schema::dropIfExists('blocks');
    }
};
