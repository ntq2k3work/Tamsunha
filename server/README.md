# Tường Nhỏ API

Laravel API for the Tường Nhỏ Flutter client. MySQL is the only application database; the mobile app calls `/api/v1` and does not connect to the database directly.

## Local setup

Requirements: PHP 8.4 with `pdo_mysql`, Composer, and Docker Compose.

```sh
cd server
composer install
cp .env.example .env
php artisan key:generate
```

Set non-empty, local-only values for `DB_PASSWORD` and `DB_ROOT_PASSWORD` in `.env`. Start the project-owned MySQL 8.4 instance and create the schema:

```sh
docker compose up -d mysql
php artisan migrate
```

The database port binds to `127.0.0.1:3309`; it is not exposed to the LAN. The named Docker volume `tamsunha_mysql_data` keeps local data between restarts. The compose project owns this volume; `docker compose down -v` removes it and permanently deletes the local database.

OTP delivery uses Laravel's `log` mailer by default. Request a code, then read it from `storage/logs/laravel.log`. To use a local SMTP catcher instead, set `MAIL_MAILER=smtp`, `MAIL_HOST=127.0.0.1`, and the catcher's port in `.env`.

Start the API and private Reverb server in separate terminals:

```sh
php artisan serve --host=0.0.0.0 --port=8100
php artisan reverb:start --host=0.0.0.0 --port=8081
php artisan schedule:work
```

Configure Flutter with an API URL that is reachable from its runtime:

```sh
# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8100 \
  --dart-define=REVERB_WS_URL=ws://10.0.2.2:8081 \
  --dart-define=REVERB_APP_KEY=tamsunha-local-key
```

Use `127.0.0.1` for an iOS simulator on the same computer. A physical device on the LAN needs the computer's private LAN IP for both URLs; the API host firewall must allow ports 8100 and 8081. Keep MySQL bound to loopback.

## Push delivery

Push is opt-in and uses Firebase Cloud Messaging. Configure the server-only `FIREBASE_SERVICE_ACCOUNT_JSON` before enabling the scheduled `push:dispatch` command. Never put a service-account key in the Flutter app or commit it to this repository. See [../docs/PUSH_DELIVERY.md](../docs/PUSH_DELIVERY.md) for provider and privacy constraints.

## API endpoints

- `POST /api/v1/auth/request-code`
- `POST /api/v1/auth/verify-code`
- `POST /api/v1/auth/logout` (bearer token)
- `POST /api/v1/rpc/{operation}` (bearer token; explicit operation allow-list)
- `POST /api/broadcasting/auth` (bearer token; private Reverb channels)
- `GET /up` (health)

Successful RPC responses preserve the client RPC envelope inside the HTTP envelope. Clients send the existing `p_*` parameter names. Actor identity always comes from the authenticated bearer token.
