# ADR-001: Flutter toolchain and application structure

- **Status:** Superseded by [ADR-002](ADR-002-laravel-mysql-api.md) at the product owner's direction; kept as the record of the original decision.
- **Date:** 2026-10-23

## Decision

Use Flutter/Dart, Riverpod, GoRouter, Flame for the wall renderer, and Supabase Flutter for the mobile client. Keep app code feature-first under `app/lib`, migrations/functions under `supabase/`, and let Presentation consume domain/application state rather than calling Supabase directly. Use authenticated RPCs for writes and minimized projections for public wall content. Realtime events invalidate canonical data; they are not a content source.

Declared package constraints:

| Package | Constraint |
|---|---:|
| `flutter_riverpod` | `^3.4.3` |
| `go_router` | `^18.1.1` |
| `flame` | `^1.38.2` |
| `supabase_flutter` | `^2.18.3` |
| `flutter_lints` | `^6.0.0` |

The package constraints are declared in `app/pubspec.yaml`, but they have not been resolved here. Generate and commit `app/pubspec.lock` only after a supported Flutter SDK completes `flutter pub get` successfully.

## Environment evidence

The current workspace does not have Flutter, Dart, Supabase CLI, Deno, or ADB/Android SDK available. A vanilla PostgreSQL migration/workflow smoke test is available, but it substitutes Supabase-specific functions and does not establish hosted RLS, Auth, Realtime, SMTP, push, or operational behavior. See [PROGRESS.md](../PROGRESS.md).

## Consequences

- Source covers the app and backend milestones, but build, analysis, unit/widget tests, Android/iOS runners, device QA, and measured performance acceptance are still open.
- Supabase credentials and service-role/admin secrets are not present in the repository or mobile bundle. Email delivery and account deletion need a separately configured DEV/BETA project.
- Account deletion immediately revokes app access and hides content; physical purge/anonymization awaits the owner's documented retention and legal policy.
- The repository has no generated Android/iOS project or dependency lockfile yet.
