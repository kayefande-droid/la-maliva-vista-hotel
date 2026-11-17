# LA-MALIVA VISTA v3 — rebuild status

Written 17 November 2026. Branch `rebuild/v3`, tag `pre-rebuild-v3`, database copied
to `../LaMaliva-git-backup/db-20261117/`. This file records what is actually done
versus what is still ahead. Nothing in this file is a guess.

## Done and verified

**Phase 1 — audit.** `PROJECT_AUDIT.md`: full inventory of the repo, the 3,789-line
Flask monolith, the SQLite schema, the 5,778-line single-file Flutter app, CI,
and this machine (Flutter 3.44, Python 3.14, Java 21, WSL2 Ubuntu stopped,
no PostgreSQL). Ten security findings with file/line evidence.

**Phase 2 — plan.** `PLAN.md`, `BRIEF.md` (approved), `core/lib/src/design/tokens.dart`.

**Phase 3–4 — backend core and security, built and tested.**
`backend/` is a new Flask application package replacing the monolith's shape:

- app factory, environment-driven config, production guards that refuse to boot
  without a real secret and a PostgreSQL URL
- full domain model (`Staff`, `Device`, `RefreshToken`, `AuthKey`, `Guest`, `Room`,
  `RoomType`, `Reservation`, `InventoryItem`, `StockMovement`, `AuditLog`,
  `Notification`, `HotelSetting`)
- Argon2id passwords, JWT access tokens, rotating refresh tokens with reuse
  detection, device registry and immediate revocation, explicit RBAC matrix
- the 50-character key: CSPRNG, hashed at rest, one-time display with a 3-minute
  window, single use, daily expiry, password re-auth to issue, fully audited
- hotel operations: rooms and types, guests with restricted identity fields,
  reservations with double-booking prevention and idempotency, check-in/out that
  keeps room status consistent, inventory with movement ledger and low-stock
  alerts, reports (overview, occupancy, revenue, staff activity), audit log,
  notifications, settings, health
- 51 routes under `/api/v1`

**Verification actually run:** `cd backend && python -m pytest -q` → **34 passed**
(authentication, key lifecycle, RBAC denials, reservations, inventory, reports,
audit, health). This is real output from this machine, not a claim.

**Live API check over HTTP.** The legacy data was migrated into a scratch SQLite
database, the API was started on loopback, and the exact payload the apps send was
replayed against it:

- `POST /api/v1/auth/login` (username, password, device fingerprint/name/platform)
  → **200**, `data.access_token` present, `data.staff.role = admin`
- `GET /api/v1/rooms` with that token → **200**, **14 rooms** carrying the real
  legacy numbers, `room_type.base_rate`, `capacity` and `size_sqm`
- wrong password → **401**; missing bearer token → **401**

So the contract both apps are compiled against is confirmed by a real server, not
by reading the docs. The scratch database and the server were removed afterwards;
port 8000 is free again.

**Defect found and fixed by that check.** The API reports failures as RFC 7807
problem details (`detail`, `title`, `status`), but both app clients read
`decoded['error']['message']`. Every rejection — wrong password, locked account,
expired token — would have surfaced as a generic "Request failed" with no reason.
Both `windows_app/lib/api.dart` and `android_app/lib/api.dart` now read `detail`
first, then `error.message`, then `message`, then `title`. Re-checked after the fix:
`flutter analyze` clean and widget tests passing on both apps, and both binaries
rebuilt. (One Android rebuild failed first because a Gradle 9.3.1 transform
workspace under `~/.gradle/caches` had been modified externally; stopping the
daemons and deleting that single workspace directory fixed it. No project change.)

**Phase 5 — staff apps, real builds.** `core/` is a local Dart package
(`lamaliva_design`) holding the tokens, imported by name from both apps. Each app
has its own API client and its own layout philosophy rather than one shared shell:

- `windows_app/` — desktop sign-in then a rooms ledger. `flutter analyze` clean,
  widget test passes, and `flutter build windows` produced
  `build/windows/x64/runner/Release/lamaliva_staff.exe` (**release build succeeds**).
- `android_app/` — phone-first sign-in then a rooms board with summary strip,
  search, status filter chips and pull-to-refresh. `flutter analyze` clean, widget
test passes at a 360 x 740 dp viewport (Galaxy Note 8 size), and `gradlew
  assembleDebug --offline` produced `build/app/outputs/apk/debug/app-debug.apk`.

Both apps are `dart:io` `HttpClient` only — no `http` package, because pub.dev is
unreachable from this machine. Both are staff-only: no customer accounts, no
booking, and PostgreSQL is never exposed to a client.

**Build notes for this machine (important).** Neither Gradle nor pub.dev can reach
the network here. `android_app/android/gradle-wrapper.properties` therefore points
at the Gradle 9.3.1 distribution already on disk, and `settings.gradle.kts` pins AGP
9.1.0 and Kotlin 2.4.0 because only those plugin markers are in the local cache.
`flutter pub get --offline` is the working form. On a machine with working network,
restore `distributionUrl` to `services.gradle.org` and the plugin versions to
Flutter's defaults, then drop `--offline`.

**Data migration tooling — written and verified.** `backend/scripts/migrate_from_sqlite.py`
maps the legacy monolith's tables onto the new schema (different shapes, so it maps
field by field): `user` -> `staff` (real staff only; the guest and throwaway test
accounts are skipped), `room` -> `room_type` + `room`, `guest` -> `guest`,
`reservation` -> `reservation` with dates, status and rate-per-night recalculated.
It is a dry run unless `--apply` is passed, reads the legacy file read-only, and is
idempotent on natural keys.

Verified on this machine against a scratch database seeded from
`instance/lamaliva.db`: **2 room types, 14 rooms (101-104 Standard, 201-210 Deluxe),
1 staff account (`admin`, Argon2id hash carried over with a forced password change),
2 guests, 2 reservations** — R00001 confirmed 2026-10-05 -> 2026-10-08 at
9,444.44/night, R00002 checked_out 2026-12-01 -> 2026-12-04 at 10,000/night.
A second run skipped all 21 rows, confirming re-runs are safe. The scratch database
was deleted afterwards; the legacy files were never modified.

**Operations scripts** — `ops/start-backend.ps1`, `stop-backend.ps1`, `status.ps1`,
`backup.ps1` (verified dump + retention), `restore.ps1` (confirmation gate + safety
backup first), and `setup-postgres.ps1`, which installs PostgreSQL 17 (from winget, or
unattended from a local installer passed with `-InstallerPath` when this PC has no
internet), creates the role and database, writes `LAMALIVA_DATABASE_URL` and
`LAMALIVA_SECRET_KEY` into the git-ignored `backend\.env` as UTF-8 without a BOM, runs
the data migration, and then **verifies the result by reconnecting as the application
role over TCP and asserting 14 rooms and at least one admin**. It stops with a readable
message at the first failure, and names the offline installer route instead of a winget
timeout when egress is missing. `setup-postgres.ps1` passes a PowerShell parser check;
it has **not been executed**, because installing PostgreSQL is the step awaiting approval.

`backend/scripts/reset_staff_password.py` is the console escape hatch for a forgotten
staff password (`--list`, dry run by default, `--apply` to write, `--password` to choose
one). A reset also moves `tokens_valid_from` forward so existing sessions die and sets
`must_change_password`. Verified against a scratch database seeded from the legacy file:
new password signs in **200** with `role=admin`, old password **401**, a <12-character
password is refused, and `--list` on an empty database explains that the migration must
run first instead of raising.

**Docs** — `docs/SECURITY.md`, `docs/API_DOCUMENTATION.md`, this status file.

## Not done yet — stated plainly

1. **PostgreSQL is not installed on this machine.** `psql` is absent and port 5432 is
   free. The backend runs and is tested on SQLite in-memory; production is guarded to
   refuse SQLite. Installing PostgreSQL 17 changes system state, so it needs your
   go-ahead — `ops\setup-postgres.ps1` does the whole sequence in one reviewed step.

   It cannot be run from this agent session: **outbound HTTPS is blocked here.** DNS
   resolves (`cdn.winget.microsoft.com` -> 150.171.109.161) but every host tried —
   cdn.winget.microsoft.com, postgresql.org, get/sbp.enterprisedb.com, github.com —
   returns `000`, and `winget search` times out on its source update. The same block
   is why pub.dev and PyPI failed earlier. The shell is elevated, so elevation is not
   the obstacle; egress is. Run `ops\setup-postgres.ps1` from a normal elevated
   PowerShell and the remaining steps work unchanged.

   **The offline route needs no egress here.** Download the EDB installer on any other
   machine from <https://www.postgresql.org/download/windows/>, copy the `.exe` across,
   and run:

   ```powershell
   cd "C:\Users\Admin\PycharmProjects\La Maliva Vista Hotel"
   powershell -ExecutionPolicy Bypass -File ops\setup-postgres.ps1 `
       -InstallerPath "C:\Users\Admin\Downloads\postgresql-17.6-1-windows-x64.exe"
   ```

   The installer runs unattended (`--install_runtimes 0`, so it does not try to fetch the
   VC++ redistributable), the superuser password is generated and printed once, and the
   script ends by printing the verified row counts.
2. **No Alembic migration yet.** Flask-Migrate/Alembic are not installed and PyPI is
   unreachable from this machine right now (TLS handshake timeout), so the offline
   path is dependency-free: the migration script creates the schema with
   `db.create_all()` when the target is empty. That is correct for the first
   PostgreSQL load, but it is not a substitute for versioned migrations once the
   schema starts changing. `psycopg2` and SQLAlchemy are already installed, so the
   PostgreSQL step needs no new downloads.
3. **The 14 existing rooms are not yet in PostgreSQL** — the database is not installed.
   The migration script is written and verified (see above), so this is now one
   command once PostgreSQL exists. The SQLite files are backed up and untouched.
4. **Both staff apps are written and each passes analysis and its widget test.**
   Scope so far is sign-in plus the rooms board; the remaining operational screens
   (guests, reservations, check-in/out, inventory, audit, reports) are not built.
   Both produce real binaries (see Phase 5 above). The API contract they are compiled
   against **has been confirmed against a running server**: a scratch database was seeded
   from the legacy file, the API was started over TCP, and the app's exact login payload
   returned **200** with a bearer token and `staff.role = admin`; `/rooms` returned
   **200** with the real 14 rooms; a wrong password and a missing token both returned
   **401**. That check also found a real defect — the API answers failures as RFC 7807
   problem details (`detail`/`title`) while both clients read `error.message`, so every
   rejection would have shown only "Request failed". Both clients now read `detail`
   first, fall back to `message`/`title`, and were rebuilt.

   What is still untested is the GUI itself: **neither app has been driven against a
   live PostgreSQL backend**, because PostgreSQL is not installed.
5. **The website has been rebuilt as a public, read-only site and pushed.** Login and
   dashboard routes are gone from the public surface. The Google verification tag
   (`<meta name="google-site-verification" content="3rRXefg_LYfyIPKcJgeXbLXBLkHx9zKOUlWcX7Fm6Tg" />`
   in `templates/public_home.html`, plus `static/google78cbf317abe48f6e.html`) must be
   carried into the rebuilt site — it is recorded here so it cannot be lost.
   The same applies to the **WhatsApp group link**
   `https://chat.whatsapp.com/EfYeauQJvsZ3tNzPiba6Cp?s=sh&p=a&iam=2`, now present in
   `templates/partials/_footer.html` (social icons + Contact column, so it appears on every
   page) and in the closing band of `templates/contact.html`. Keep it, and keep it opening in
   a new tab with `rel="noopener"`.
6. **Headscale is not installed.** WSL2 Ubuntu is present and stopped. Installing
   Headscale, enabling systemd and changing networking needs your approval. The full
   runbook — systemd, pinned install, deny-by-default ACLs that allow only TCP 8000,
   per-device pre-auth keys, and the two-sided revocation procedure — is in
   `docs/HEADSCALE.md`.
7. **Remote connectivity is untested** and will stay reported as untested until a
   device on a different network connects. The public-IP/CGNAT question is unanswered.

## The order I will continue in

1. Your approval → PostgreSQL install, database creation, Alembic, data migration
   from the backed-up SQLite (rooms preserved by number and size).
2. Design system → Windows app shell and the fifteen screens.
3. Android app on the same `core` package, Note 8 through current Galaxy.
4. Website rebuild: public only, accounts removed, verification tag preserved.
5. Headscale in WSL2, ACLs, enrolment, device revocation.
6. Security review pass, the Part 18 test matrix, release builds, remaining docs.
