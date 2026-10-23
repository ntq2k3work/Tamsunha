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
        Schema::create('encouragements', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('note_id')->constrained('notes')->restrictOnDelete();
            $table->foreignUuid('sender_id')->constrained('users')->restrictOnDelete();
            $table->string('template_key', 24);
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['note_id', 'sender_id']);
            $table->index(['note_id', 'created_at', 'id'], 'encouragements_note_time_idx');
        });

        Schema::create('conversations', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('participant_low')->constrained('users')->restrictOnDelete();
            $table->foreignUuid('participant_high')->constrained('users')->restrictOnDelete();
            $table->foreignUuid('source_note_id')->constrained('notes')->restrictOnDelete();
            $table->foreignUuid('created_by')->constrained('users')->restrictOnDelete();
            $table->string('status', 24)->default('active');
            $table->foreignUuid('last_sender_id')->nullable()->constrained('users')->nullOnDelete();
            $table->unsignedTinyInteger('streak_count')->default(0);
            $table->timestamp('last_message_at')->nullable();
            $table->timestamps();
            $table->unique(['participant_low', 'participant_high']);
            $table->index(['participant_low', 'updated_at', 'id'], 'conversations_low_updated_idx');
            $table->index(['participant_high', 'updated_at', 'id'], 'conversations_high_updated_idx');
        });

        Schema::create('messages', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('conversation_id')->constrained('conversations')->restrictOnDelete();
            $table->foreignUuid('sender_id')->constrained('users')->restrictOnDelete();
            $table->uuid('client_request_id');
            $table->text('body');
            $table->string('status', 24)->default('pending_review');
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['sender_id', 'client_request_id']);
            $table->index(['conversation_id', 'created_at', 'id'], 'messages_conversation_created_idx');
        });

        Schema::create('notifications', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('recipient_id')->constrained('users')->cascadeOnDelete();
            $table->string('notification_type', 24);
            $table->uuid('source_id');
            $table->foreignUuid('conversation_id')->nullable()->constrained('conversations')->cascadeOnDelete();
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('read_at')->nullable();
            $table->unique(['recipient_id', 'notification_type', 'source_id'], 'notifications_dedupe');
            $table->index(['recipient_id', 'created_at', 'id'], 'notifications_recipient_time_idx');
        });

        Schema::create('rate_limit_events', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->foreignUuid('actor_id')->constrained('users')->cascadeOnDelete();
            $table->string('operation', 80);
            $table->timestamp('occurred_at')->useCurrent();
            $table->index(['actor_id', 'operation', 'occurred_at'], 'rate_limit_actor_operation_time_idx');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('rate_limit_events');
        Schema::dropIfExists('notifications');
        Schema::dropIfExists('messages');
        Schema::dropIfExists('conversations');
        Schema::dropIfExists('encouragements');
    }
};
