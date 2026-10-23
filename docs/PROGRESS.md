# Tường Nhỏ implementation status

**Updated:** 2026-10-23  
**Source of truth:** [ALL_IN_ONE_SPEC.md](../ALL_IN_ONE_SPEC.md)  
**Status:** The active app backend has been ported to Laravel 13, Sanctum, MySQL 8.4, and Reverb under `server/`. Local migrations are applied. Account-erasure policy, provider credentials/delivery acceptance, metrics/operations, Flutter compilation/device acceptance, and release gates remain open. Release acceptance is **not verified**; see blockers below.

## Implemented in source

- **M0 foundation:** Flutter app manifest and lints, Riverpod/GoRouter bootstrap, API URL validation, CI workflow, theme tokens, paper components, handwritten domain DTOs, and serialization/geometry tests.
- **M1 wall:** Flame world/camera, pan and anchored pinch zoom, deterministic note rendering, reduced motion, LOD/tile cache, placement preview, note reader transition, and offline-only demo.
- **M2 shared wall and auth:** Laravel email OTP API, consent/age gate, authenticated API repositories, canonical cell/tile logic, server placement quota/idempotency, note edit/delete/chat preference, private tile projection, discovery, and client cache invalidation.
- **M3 engagement:** one-time encouragement, cursor-backed inbox/conversation repositories, server-enforced three-message streak, notification read state, private Reverb invalidation, reconnect refresh, opening-note context that is returned only while the note is published, and chat safety actions.
- **M4 safety source:** block/report from notes, conversations, and individual messages; report the anonymous user through a note or conversation context without sending the user's ID to the app; atomic report-and-block; note/message moderation queue and audited actions; protected moderator routes; report-based account suspension with push-token removal; and account deletion request/session revocation entry point. Retention purge/anonymization and legally required export handling remain undecided and unimplemented.
- **M4 push/observability source:** explicit push opt-in and OS permission flow; FCM token registration/refresh/unregister; server-only outbox claim/completion with `SKIP LOCKED`, backoff and invalid-token cleanup; neutral FCM/APNs payloads; scheduled `push:dispatch`; push taps route to inbox; content-free Crashlytics handlers and an event-name-only analytics allow-list, both gated off by default. FCM credentials and delivery/device acceptance remain open.
- **Laravel database:** MySQL migrations for accounts, wall, engagement, safety/moderation, and push outbox; app data is accessed through authenticated API operations; role-checked moderator services and audited actions. A local MySQL 8.4 container is running at `127.0.0.1:3309`; all migrations applied successfully. MySQL workflow and concurrency tests have not been run.
- **Migration reference:** `supabase/` remains temporarily as an inactive SQL behavior/test reference. The Flutter app and `server/` have no runtime dependency on it.

## Checks run

### Current Laravel/MySQL implementation

- `php artisan migrate --force` — **PASS** on the project-owned MySQL 8.4 container on 2026-10-23; all eight Laravel migrations applied.
- `php artisan route:list --path=broadcasting`, `php artisan migrate:status`, and `php artisan schedule:list` — **PASS**; authenticated Reverb auth route is registered, migrations are current, and `push:dispatch` is scheduled every minute.
- PHP syntax checks were run on the changed services/controllers/routes; no Laravel feature/unit tests were run.
- Flutter/Dart format, dependency resolution, analyzer, tests, Android/iOS builds, and device checks — **NOT RUN**; Flutter/Dart is unavailable in this workspace.

### Historical Supabase SQL reference checks

- `scripts/test-supabase-smoke.sh` — **PASS** on 2026-10-23 after the final push-migration change, in a disposable PostgreSQL 14 database with Supabase-specific schemas/functions stubbed. It applied all five migrations and exercised consent, placement collision/idempotency, note edit locks, moderator checks, privacy-minimized DTOs, unread state, message streaks, source-note visibility, note/conversation user reports without client user IDs, rejection of direct user-ID reports, user-ID redaction in the moderator queue, atomic report/block, report-based suspension/audit/push-token cleanup, default-off push preference, token opt-in enforcement, outbox enqueue/revocation, deletion queue state, and other core SQL workflows. This is not a Supabase CLI reset, production-project test, RLS-policy test under real Supabase Auth, or Realtime authorization test.
- `scripts/test-supabase-concurrency.sh` — **PASS** on 2026-10-23 in a disposable PostgreSQL 14 database with stubbed Supabase schemas. Independent `psql` sessions confirmed one winner/one `SLOT_OCCUPIED` on a concurrent cell collision, 3 accepted messages/one `MESSAGE_LIMIT_REACHED` for four concurrent sends, and two concurrent identical placement retries resolving to one note. Re-run against Supabase Auth before G2/G3.
- `bash -n scripts/test-supabase-smoke.sh scripts/test-supabase-concurrency.sh` — **PASS**.
- `node --check supabase/functions/dispatch-push/index.ts` — **PASS** for Node syntax parsing only; this is not Deno type/runtime validation.
- Flutter format, dependency resolution, analyzer, Dart tests, Android/iOS builds, and device checks — **NOT RUN**. Flutter/Dart and generated platform runners are absent in this workspace; only 2 GB disk remains, so an SDK install was not attempted.
- Supabase local-stack / DEV-project and Edge Function checks — **NOT RUN**. The Supabase source is inactive and retained only as a migration reference.

## Release blockers and next owners

1. **App/toolchain owner:** use a workspace with Flutter stable 3.47+ / Dart 3.12+, generate Android/iOS runners, resolve dependencies and commit `app/pubspec.lock`; run format, `flutter analyze`, `flutter test`, and Android build. The current environment cannot validate Dart compilation.
2. **Mobile QA owner:** run the M1 interaction and accessibility checklist on at least two Android device classes; verify pan/pinch anchoring, 30 reader open/close cycles, keyboard/back, TalkBack, text scaling, reduced motion, reconnect, and race cases. Capture screenshots/video and measured frame/memory results in `PERF_REPORT.md`. iOS requires a separate macOS/Xcode pass.
3. **Backend owner:** run MySQL-backed API authorization and concurrency checks for placement collisions, message streaks, idempotency, private Reverb channels, session revocation, backups and restore before release. The former Supabase project checks no longer apply.
4. **Push/observability owner:** configure Firebase Android/iOS apps, APNs credentials, server-only Firebase service-account JSON, and the Laravel one-minute scheduler; verify opt-in, foreground/background, tap-to-inbox, token rotation, opt-out, retry and invalid-token cleanup on devices. Moderation/account-warning push events, approved KPI aggregation/retention, SQL slow-query alerts, budget alerts, and backup/restore drills still need policy/configuration. Firebase Crashlytics and Analytics source adapters are off by default and have not been enabled or verified.
5. **Safety/legal owner:** choose and document deletion retention/purge/anonymization and any export-request workflow; the current implementation immediately disables access and hides content, while the moderator queue only marks a request processing or held. Review and publish the final privacy notice, terms, community rules, support contact, Vietnam legal applicability, and store UGC obligations.
6. **Operations owner:** name the moderation/incident-response owner, approve on-call and escalation procedures, and exercise report/block/moderation workflows before inviting beta users.

## Known contract limits

- PostgreSQL enforces UTF-8 byte caps and a conservative Unicode code-point ceiling; the Flutter client counts grapheme clusters. Rare multi-code-point graphemes can be conservatively rejected by the server. Exact extended-grapheme parity needs a reviewed server-side Unicode segmentation implementation.
- SQL workflow smoke uses Supabase stubs, so it proves migration syntax and business-function behavior only within that harness. It is not evidence of hosted Supabase RLS, Realtime channel authorization, SMTP, push, or provider operations.
- Push outbox claim/retry is idempotent at the database-job layer, but FCM does not provide exactly-once delivery. A provider timeout after accepting a send can still cause a retry; per-type collapse keys reduce duplicate pending alerts and the inbox remains authoritative.
- The account deletion endpoint immediately disables access and hides notes, then queues a request for moderator processing. Final purge/anonymization and export behavior are intentionally not implemented until the retention/legal policy is decided.

Do not mark G0–G4 or production readiness passed from source code or the SQL smoke alone. Per the spec, the deliverable remains **IMPLEMENTED — RELEASE BLOCKED** until the listed owner gates are closed.
