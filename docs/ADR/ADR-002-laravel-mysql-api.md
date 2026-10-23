# ADR-002: Laravel API and local MySQL backend

- **Status:** Accepted by product owner; local API and MySQL implementation is in place.
- **Date:** 2026-10-23
- **Supersedes:** the Supabase/PostgreSQL choice in ADR-001 and DEC-12.

## Decision

Run a single Laravel 13 monolith in `server/` with MySQL 8.4/InnoDB as its database. The Flutter app calls a versioned HTTPS JSON API and never connects to MySQL directly. Use Laravel Sanctum bearer tokens for mobile sessions, expiring email OTPs for passwordless login, Laravel migrations for schema, transactional application services for privileged writes, and Laravel Reverb private channels for content-free invalidation signals. Local development connects the API to a MySQL instance bound to loopback; the same API may later be deployed behind HTTPS without changing business rules.

Existing product invariants remain in force: the API derives the acting user from the verified token, author/user identifiers are not exposed in wall DTOs, placement and messaging remain transactional/idempotent, safety operations remain auditable, and event payloads never contain note/chat bodies. MySQL credentials and mail/provider secrets are server-only.

## Consequences

- The app uses Laravel API repositories, Sanctum bearer tokens, MySQL migrations, Reverb authorization, and a scheduled Laravel push command. Supabase runtime, migrations, functions, and test artifacts have been removed from the repository.
- This ADR and the architecture update at the top of `ALL_IN_ONE_SPEC.md` preserve the migration history. Do not recreate or run the superseded Supabase implementation.
- A local MySQL server is reachable only from the local host/network. Public use later requires deploying the API and database with HTTPS, backups, mail delivery, secrets, and operations ownership.
- No existing cloud database user data migration is planned; the local project has no configured production database or project credentials.

## Development verification

The available workspace has PHP 8.4, Composer 2.8, MySQL 8.4, Docker, and Node 22. It has no Flutter/Dart SDK. Laravel 13.38.0, Sanctum 4.3.3, and Reverb 1.12.0 are installed. A project-owned MySQL 8.4 container is running on loopback port 3309 and every Laravel migration has been applied. Static route inspection confirms the authenticated API and Reverb authorization endpoints. No Laravel tests, Flutter builds, or device checks have been run; MySQL authorization/concurrency behavior still needs its own verification before release.

References: [Laravel mobile API authentication](https://laravel.com/docs/13.x/sanctum#mobile-application-authentication), [Laravel database transactions](https://laravel.com/docs/13.x/database#database-transactions), [Laravel private broadcasting](https://laravel.com/docs/13.x/broadcasting#authorizing-channels), [Laravel Reverb](https://laravel.com/docs/13.x/reverb).
