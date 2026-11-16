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

**Operations scripts** — `ops/start-backend.ps1`, `stop-backend.ps1`, `status.ps1`,
`backup.ps1` (verified dump + retention), `restore.ps1` (confirmation gate + safety
backup first).

**Docs** — `docs/SECURITY.md`, `docs/API_DOCUMENTATION.md`, this status file.

## Not done yet — stated plainly

1. **PostgreSQL is not installed on this machine.** `psql` is absent. The backend
   runs and is tested on SQLite in-memory; production is guarded to refuse SQLite.
   Installing PostgreSQL 17 changes system state, so it needs your go-ahead.
2. **No Alembic migration yet.** Flask-Migrate/Alembic are not installed and PyPI is
   unreachable from this machine right now (TLS handshake timeout), so the offline
   path is dependency-free. Migrations land as soon as installs work.
3. **The 14 existing rooms, 6 accounts and 2 reservations are not migrated.** The SQLite
   files are backed up and untouched. Migration is a scripted step after step 1.
4. **Neither Flutter app exists yet.** `windows_app/` and `android_app/` are empty
   directories; `core/` holds design tokens only. The old `mobile_app/` is untouched.
   This is the largest remaining piece of work.
5. **The website still contains customer accounts, booking and the dashboard.** It is
   live and unchanged. The Google verification tag
   (`<meta name="google-site-verification" content="3rRXefg_LYfyIPKcJgeXbLXBLkHx9zKOUlWcX7Fm6Tg" />`
   in `templates/public_home.html`, plus `static/google78cbf317abe48f6e.html`) must be
   carried into the rebuilt site — it is recorded here so it cannot be lost.
   The same applies to the **WhatsApp group link**
   `https://chat.whatsapp.com/EfYeauQJvsZ3tNzPiba6Cp?s=sh&p=a&iam=2`, now present in
   `templates/partials/_footer.html` (social icons + Contact column, so it appears on every
   page) and in the closing band of `templates/contact.html`. Keep it, and keep it opening in
   a new tab with `rel="noopener"`.
6. **Headscale is not installed.** WSL2 Ubuntu is present and stopped. Installing
   Headscale, enabling systemd and changing networking needs your approval.
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
