# LA-MALIVA VISTA HOTEL — A Taste of Paradise 🌴

Luxury hotel platform for **LA-MALIVA VISTA HOTEL, Buea, Cameroon** — one backend,
three experiences: the **public website + PWA**, the **native Android app**, and the
**native Windows desktop app**.

<p align="center">
  <img src="static/readme_banner.png" alt="LA-MALIVA VISTA HOTEL — A Taste of Paradise · Buea, Cameroon" width="100%">
</p>

> All three surfaces share the same database through the website's REST API —
> book on the website and it appears in the app; register a guest in the app and
> it lands in the website dashboard instantly.

---

## ✨ Highlights

| Area | What you get |
|---|---|
| **Public website** | Luxury dark-navy/burnt-orange design, room gallery, online booking, contact page with live Google-Maps link |
| **PWA** | Installable from the browser, works offline with cached rooms & pages, live connectivity banner |
| **Android & Windows apps** | Same account works everywhere — sign in once, bookings and receipts sync both ways |
| **Live growth analytics** | Every signup and every app download (APK / Windows / PWA install) streams instantly to the administrator: real-time notification bell alerts + a live dashboard panel with counters and toasts |
| **6 design styles** | Royal Navy · Sunset Amber · Emerald Royale · Plum Noir · Ocean Teal · Graphite Noir — switchable on web **and** app |
| **Animated backgrounds** | Each style has its own ambient motion (waves, embers, petals, orbs, bubbles, streaks) |
| **Invoices & receipts** | Branded PDF invoices — view, **download**, and **print** from the website and from both apps |
| **Notifications center** | In-app inbox with messages from the La-Maliva team and hotel administration |
| **Real email delivery** | Branded navy/gold emails sent from `lamalivav@gmail.com` via SMTP: **email verification after signup** (guests confirm before sign-in) and **password reset** links — see `docs/EMAIL_SETUP.md` |
| **In-app updates** | Account → *Check for updates* notifies users when a newer build ships and takes them straight to the download |
| **Offline-first** | Rooms, prices and menu cached on device; staff can keep registering guests offline and everything syncs when the internet returns |
| **Role-aware access** | Guest, staff and administrator experiences — staff/admin tools are simply invisible to guests |

## 📈 Admin Live Growth — signups & downloads across every app

When a new customer registers — **on the website, in the PWA, in the Android app
or the Windows app** — every administrator account receives a live notification
(🆕 in the bell, unread badge), and the admin **Dashboard** shows a *Live Growth*
panel that polls every 6 seconds with:

- **Registered accounts** (all apps) — broken down by source (Web/PWA vs App)
- **App downloads** (all platforms) — Android APK, Windows EXE, PWA installs
- **Live feed** of events + instant toast pop-up for each new signup or download

How events are captured:

| Event | Source | Endpoint |
|---|---|---|
| Website signup | form field auto-set (`web` / `pwa` via detection script) | `/signup` |
| Native-app signup | app sends `source: android\|windows` | `/api/auth/register` |
| APK / Windows download | counted when the bundle is served | `/downloads/<platform>`, `/apk`, `/exe` |
| PWA install | browser `appinstalled` event, reported once per browser | `/api/pwa-install` |
| Native-app first launch | app reports install once per device | `/api/install` |

Endpoints (admin/staff only): `GET /api/admin/growth`,
`GET /api/admin/growth/events?after_id=<id>` (lightweight live polling).

## 🏗️ Architecture

```
                [ Central Backend — Flask + SQLAlchemy ]
                 la-maliva-vista-hotel.onrender.com
                          /                \
                 (REST API + token)   (server-rendered pages)
                        /                    \
        [ Android app (Flutter) ]       [ Website frontend + PWA ]
        [ Windows app (Flutter) ]        ← same REST API for sync →
```

- **Backend** — `app.py` (Flask), SQLite via SQLAlchemy, JWT-style bearer tokens for the app,
  session auth for the web, CSRF protection, rate limiting, hardened headers.
  Growth analytics live in the `AppEvent` stream + `User.signup_source`.
- **Email** — `mailer.py` builds the branded navy/gold messages (verification + password reset)
  and delivers via SMTP using environment variables configured on Render.
- **Native apps** — `mobile_app/` (Flutter/Dart), one codebase producing the APK and the
  Windows EXE; talks to the website API only.
- **Service worker** — `static/sw.js` caches the shell for offline PWA use.

## 📦 Downloads

Get the latest builds (version matches the site banner) from the website's
**[Downloads page](https://la-maliva-vista-hotel.onrender.com/downloads)**:

| Platform | File | Install |
|---|---|---|
| Android 8.0+ | `la-maliva-vista-<version>.apk` | Tap the APK, allow “install unknown apps” for your browser, install |
| Windows 10/11 | `La-Maliva-Vista-<version>-windows.zip` | Unzip, run `lamaliva_app.exe` |
| Any browser | PWA | Open the site → “Install app” / Add to Home Screen |

The apps self-check for updates against `/api/version` — when a new build is
published here, users get a notification and a one-tap path to the new download.

## 🚀 Development

```bash
# Website
pip install -r requirements.txt
python app.py                # http://127.0.0.1:5000

# Native apps (Flutter)
cd mobile_app
flutter pub get
flutter run                  # device/emulator
flutter build apk --release  # Android APK
flutter build windows --release
```

Release bundles are staged into `static/releases/` and served by the downloads page.
The version lives in `app.py` (`APP_VERSION`), `mobile_app/pubspec.yaml`, `mobile_app/lib/main.dart`
(`kAppVersion`) and `static/sw.js` — bump all four together.
`static/readme_banner.png` is generated art (logo + brand palette); regenerate with
any image editor if the brand palette changes.

## 📄 User guide

Guest-facing help lives inside the product: the app's Account tab and the website's
**User Manual** page cover everything a guest needs — signing in, booking, receipts,
invoices, themes, notifications and updates.

---
© La-Maliva Vista Hotel · Buea, Cameroon · Opposite Fako Heart Entrance, GRA Bokwaongo
