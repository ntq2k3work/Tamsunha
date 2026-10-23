# Push delivery and telemetry setup

## Current source behavior

- The in-app notifications preference defaults to off. The rollout migration resets the previous default-on preference and removes its unconsented device tokens; enabling it then requests OS permission. Inbox notifications remain available when push is off or denied.
- A permitted Android/iOS install registers its FCM token through `register_device`. The app sends a random install key hash, token, and platform only. Sign-out and deletion attempt to unregister and remove the local FCM token; disabling the server preference also deletes server tokens and pending deliveries.
- New inbox notification rows enqueue one private outbox item per currently registered device. `dispatch-push` claims up to 50 items with a short lease, retries transient failures with exponential backoff, and deletes tokens FCM reports as unregistered. Turning push off removes the server token and queued outbox rows; a delivery already claimed and in flight at the provider may still arrive once.
- Push payloads use fixed Vietnamese copy, a static inbox route, and static event names. They do not include note/message text, account IDs, conversation IDs, email addresses, or device tokens. Android and APNs collapse notifications by event type; the inbox remains the full history.
- Crash reports and Firebase Analytics are disabled unless their Dart define is explicitly enabled. Analytics events are a fixed allow-list with no event properties or user identifier. Do not enable either collection before the data notice and cross-border/provider review is approved.

## Configure the mobile app

After generating the Android and iOS runners, configure the Firebase project from `app/`:

```sh
flutterfire configure --platforms=android,ios
flutter pub get
```

Keep the generated native Firebase configuration out of public repositories if the project policy requires it; never add a service-account private key to the app. For Apple push, enable the Push Notifications capability and upload the project's APNs authentication key in Firebase. Test on physical Android and Apple devices before enabling delivery.

Firebase is intentionally off in source builds. A configured mobile build can enable it with:

```sh
flutter run \
  --dart-define=FIREBASE_ENABLED=true \
  --dart-define=CRASH_REPORTING_ENABLED=true \
  --dart-define=PRODUCT_ANALYTICS_ENABLED=true
```

Enable only the features whose owners have approved the provider and disclosures. `FIREBASE_ENABLED` is required for token registration; crash reporting and analytics each default to off. Analytics sends only the event names from `ProductEvent`, without coordinates, record IDs, note/chat content, email, or user ID. Firebase may still collect app-instance/device metadata when collection is enabled; include that in privacy and store disclosures.

## Configure the Laravel dispatcher

Set the server-only Firebase service-account JSON from an approved secret manager as `FIREBASE_SERVICE_ACCOUNT_JSON`. It must contain the Firebase service account's `client_email`, `private_key`, and `project_id`, with only the permission required to send FCM messages. Never put it in the Flutter app, `.env.example`, logs, or source control.

Laravel registers `php artisan push:dispatch --limit=50` every minute. Run `php artisan schedule:work` in local development or use the deployment platform's scheduler to invoke `php artisan schedule:run` every minute. The command claims outbox rows directly from MySQL, sends neutral Firebase HTTP v1 messages, and records aggregate counts only; it does not log message payloads or tokens. If service-account JSON is absent or invalid, the command skips delivery without claiming rows.

The SQL outbox deduplicates each notification/device pair, serializes concurrent workers with `SKIP LOCKED`, and retries at most eight times. FCM itself does not offer exactly-once delivery: a timeout after provider acceptance can still cause a later retry. A delivery already claimed by the dispatcher also cannot be recalled if the user disables push while the provider request is in flight. Collapse keys reduce duplicate alerts of the same type, while the inbox remains authoritative. Verify this behavior, invalid-token cleanup, preference revocation, and provider retries on a dedicated DEV project before beta.

## Remaining owner gates

- Generate runners, resolve `app/pubspec.lock`, run Flutter format/analyzer/tests and Android/iOS builds.
- Configure Firebase project IDs, Android package/iOS bundle IDs, APNs key, server-only service-account JSON, and the protected one-minute Laravel schedule.
- Approve privacy/store disclosure, cross-border data handling, telemetry retention, support and incident response before enabling Crashlytics or Analytics.
- Run two-device push delivery tests for opt-in, deny, foreground/background, tap-to-inbox, sign-out, token refresh, suspension, deletion, invalid token, retry, and duplicate/coalesced delivery.
- Product analytics currently emits event names only. KPI aggregation/retention, SQL slow-query alerts, budget alerts, backup/restore drills, and a production service-status contact still need owner configuration.
