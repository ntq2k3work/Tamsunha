# Tường Nhỏ

Tường Nhỏ is a Flutter app for an adult-only anonymous journaling community on one persistent 2D wall. Product and security contracts live in [ALL_IN_ONE_SPEC.md](ALL_IN_ONE_SPEC.md).

## Implementation status

The active architecture is a Laravel API with local MySQL and private Laravel Reverb channels. The Flutter client talks only to that API. The earlier Supabase/PostgreSQL implementation is no longer used by the app; [ADR-002](docs/ADR/ADR-002-laravel-mysql-api.md) records the migration decision. Local API and MySQL setup is in [server/README.md](server/README.md).

The project still needs Flutter compilation/device acceptance, configured Firebase credentials and device push acceptance, an approved account-deletion purge/export policy, operational checks, and legal/store review before release. See [docs/PROGRESS.md](docs/PROGRESS.md), [docs/PUSH_DELIVERY.md](docs/PUSH_DELIVERY.md), and [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

## Flutter setup

On a development machine with Flutter stable 3.47+ and Dart 3.12+:

```sh
cd app
flutter create --org app.tuongnho --project-name tuong_nho --platforms android,ios .
flutter pub get
flutter analyze
flutter test
```

`app.tuongnho` is a development placeholder; confirm the Android package and iOS bundle identifiers before distributing a build. `pubspec.lock` and platform runners have not been generated. Configure `API_BASE_URL` with a Dart define; local addresses for emulators and devices are in [server/README.md](server/README.md). Never place a database or Firebase service-account credential in the mobile app.

For an approved Firebase DEV/BETA project, configure the native apps with `flutterfire configure --platforms=android,ios` after creating the platform runners. Push, crash reporting, and analytics are feature-gated; setup, protected server secrets, and the scheduled dispatcher are described in [docs/PUSH_DELIVERY.md](docs/PUSH_DELIVERY.md). Do not enable crash or analytics collection until the privacy/store disclosures and provider review are approved.

## Backend

Follow [server/README.md](server/README.md) to start the local MySQL database, apply Laravel migrations, and run the API and Reverb server. Do not point local development commands at a production database.

## Product invariants

- Everyone sees the same fixed note coordinates on one endless wall; the wall is not a feed.
- Small wall notes never expose content or author identity. Content is fetched only when a note is opened.
- Posting, encouragement, conversation limits, block/report, and moderator operations are enforced by trusted backend operations.
- A public or closed beta requires the safety, privacy, moderation, legal, operational, and device gates in the specification.
