# Open decisions and release gates

Implementation status and observed test results are recorded in [PROGRESS.md](PROGRESS.md). These are the decisions and external checks still needed; none should be silently inferred from local source code.

## Before an executable build

- Build in a workspace with Flutter stable 3.47+ / Dart 3.12+, generate platform runners, resolve/lock dependencies, and pass formatting, analyzer, unit/widget tests, and Android build.
- Confirm the permanent Android application ID and iOS bundle ID; `app.tuongnho` is only a development placeholder.
- Deploy the Laravel API with a dedicated MySQL database, HTTPS, email SMTP, and Reverb. Keep database and Firebase service-account secrets on the server; the Flutter app only receives the public API and WebSocket addresses.
- Configure Firebase Android/iOS app IDs and APNs credentials. Keep `FIREBASE_ENABLED`, `CRASH_REPORTING_ENABLED`, and `PRODUCT_ANALYTICS_ENABLED` off until the corresponding provider and disclosure approvals are in place.
- Run MySQL-backed API authorization/concurrency checks, private-channel authorization, deletion revocation, backup/restore, and budget-alert checks.

## Before closed beta

- Configure `FIREBASE_SERVICE_ACCOUNT_JSON` on the server and run the scheduled Laravel `push:dispatch` command; verify opt-in, permission denial, foreground/background delivery, tap-to-inbox, sign-out, deletion, token refresh, invalid-token cleanup and retry behavior on two devices. The database outbox is idempotent, but provider delivery is at-least-once.
- Decide whether moderation/account-warning notifications are needed and approve their neutral copy; these event producers are not wired in source yet.
- Approve Crashlytics/Analytics provider disclosures, then test the content-free handlers and event allow-list. Choose event retention and implement KPI aggregation; current adapters are disabled by default.
- Decide a lawful retention, purge/anonymization, and backup schedule for account deletion. Current behavior immediately disables access and hides content; moderator actions only start processing or hold a request.
- Approve and publish final Terms, Privacy Notice, Community Rules, support contact, data disclosures, and Vietnam legal/store review.
- Assign the moderation and incident-response owner, hours, escalation path, and reporting SLA; test the operating procedure.
- Complete two-device Android QA, accessibility and text-scaling checks, offline/reconnect and race checks, and publish `PERF_REPORT.md`; complete a separate iOS pass before iOS release.

## Engineering note

The server currently uses a conservative Unicode code-point limit plus UTF-8 byte limits while the client counts grapheme clusters. Exact extended-grapheme parity requires a reviewed server-side Unicode segmentation implementation; test combining marks and emoji sequences before public release.
