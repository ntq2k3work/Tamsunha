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
        Schema::create('push_delivery_outbox', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('notification_id')->constrained('notifications')->cascadeOnDelete();
            $table->foreignUuid('device_id')->constrained('user_devices')->cascadeOnDelete();
            $table->string('status', 16)->default('pending');
            $table->unsignedTinyInteger('attempt_count')->default(0);
            $table->timestamp('available_at')->useCurrent();
            $table->timestamp('locked_until')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->string('last_error_code', 32)->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->unique(['notification_id', 'device_id'], 'push_outbox_notification_device_unique');
            $table->index(['status', 'available_at', 'created_at', 'id'], 'push_outbox_claim_idx');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('push_delivery_outbox');
    }
};
