# ADR-001: Flutter toolchain and application structure

- **Status:** Superseded by [ADR-002](ADR-002-laravel-mysql-api.md).
- **Date:** 2026-10-23

This record captures the original app structure decision: Flutter/Dart, Riverpod, GoRouter, Flame, and feature-first code under `app/lib`. Its original Supabase/PostgreSQL backend choice was replaced by ADR-002.

The app structure and product invariants remain relevant. Superseded backend packages, setup instructions, migrations, functions, and checks were removed; use [server/README.md](../../server/README.md) and ADR-002 for the active backend.
