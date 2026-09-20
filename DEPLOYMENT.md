# LA-MALIVA VISTA HOTEL — Deployment & Operations

## 1. Deploying on Render (via GitHub)

The repo deploys as a Python web service:

- **Build command:** `pip install -r requirements.txt`
- **Start command:** `gunicorn app:app` (already in `Procfile`)
- **Python version:** from `runtime.txt`

### Required environment variables

| Variable | Purpose | Example |
|---|---|---|
| `SECRET_KEY` | Session signing — **set a long random value** | `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `ELEVATED_ACCESS_PASS` | **Secret pass** required by staff/admin on the login form | A strong phrase, e.g. `Fako-Ridge-2026!` |
| `SMTP_HOST` | SMTP server for verification emails | `smtp.gmail.com` |
| `SMTP_PORT` | `587` (TLS) or `465` (SSL) | `587` |
| `SMTP_USER` | Sending mailbox | `no-reply@lamaliva.com` |
| `SMTP_PASSWORD` | Mailbox password / **app password** | — |
| `MAIL_FROM` | Display sender | `La-Maliva Vista <no-reply@lamaliva.com>` |

> **Gmail tip:** enable 2FA and create an *App Password*; use it as `SMTP_PASSWORD`.

Optional (existing features): `MTN_MOMO_*` variables for Mobile Money payments.

If `SMTP_*` is omitted, signups still work but verification emails are not sent —
the server logs the verification link instead. **Set SMTP on production.**

## 2. How the auth gates work

- **Signup** → real-email check (syntax → disposable blocklist → live DNS MX/A) →
  account created unverified → branded verification email with 24 h token link.
- **Login (any role)** → blocked until `email_verified` is true. A "Resend
  verification" panel appears on the login screen for pending accounts.
- **Staff/Admin login** → additionally requires the **secret pass** (GATE 2).
  It is compared against `ELEVATED_ACCESS_PASS` (app-wide) or the per-user
  `access_secret_hash` fallback. The field auto-reveals when the operator ID
  starts with `admin`/`staff`, and always appears after a failed attempt.
- Seeded/internal accounts (`admin`, users created in the Users panel) are
  pre-verified automatically.

## 3. Native builds (APK / EXE)

GitHub Actions workflow `.github/workflows/build-release.yml` produces:

- `La-Maliva-Vista-Setup-<version>.exe` — PyInstaller onedir, zipped
- `la-maliva-vista-<version>.apk` — TWA (trusted web activity) wrapper via
  [Bubblewrap](https://github.com/GoogleChromeLabs/bubblewrap), signed with a
  generated keystore
- Attached automatically to a GitHub Release when you **push a tag**:

```bash
git tag v2.0.0 && git push origin v2.0.0
```

Version single-source-of-truth: `APP_VERSION` in `app.py` — it feeds the
downloads page cards and `/api/version`.

Drop built binaries into `static/releases/` (or let the workflow attach them)
and the `/downloads` page serves them at `/downloads/android` and
`/downloads/windows`.

## 4. PWA / offline

- `static/sw.js` — offline-first service worker (precached shell, SWR assets,
  network-first pages with `/offline` fallback). Bump `VERSION` inside it when
  releasing.
- `manifest.json` — standalone display, maskable icons, app shortcuts.
- Register once per session; the login/signup/home pages register `/sw.js`.

## 5. Local development

```bash
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
python app.py                 # http://127.0.0.1:5000
```

Default seeded admin: `admin / admin123` (**change immediately**) + secret pass
`MALIVA-2026` (override with `ELEVATED_ACCESS_PASS`).
