# Install / build notes — native Windows desktop app

Short note about the native Windows build so the online release stays lean and safe.

## What you get

- A **single .exe** you can unzip anywhere and run — no install wizard, no installer clutter.
- Launched from the `static/releases/` folder on the website, or copied from the
  release page at **https://onrender.com/cloud** (replace with the real URL).

## Why it's kept small

The native Windows build must not be heavy — a big package is hard to download,
slow to update, and more likely to get flagged by SmartScreen or over the site's
bandwidth. The build intentionally:

- Bundles only what the app needs to run (Python runtime, templates, static assets,
  instance data).
- Does **not** bundle old release binaries, dev artifacts, or build/ dist/ folders.
- Uses PyInstaller onefile mode with max compression so the .exe + zip stay lean.

## What to do after downloading

1. Download `La-Maliva-Vista-Setup-v2.3.9-windows.zip`.
2. Extract (right-click → Extract All, or 7-Zip / Windows Explorer).
3. Run `La-Maliva-Vista-Server.exe`.
4. If Windows SmartScreen warns, choose **More info → Run anyway** (the exe is
   self-contained and unsigned in this build).

## Release-signed / online-safe release

For a clean online release:

- Sign the EXE (or the zip) with a code-signing certificate so Windows / SmartScreen
  stop showing warnings.
- Consider publishing the Windows build as a **GitHub Release** asset instead of
  committing the binary into git — that keeps the repo small and avoids pushing big
  files every time.
- When pushing binaries, keep each file under platform limits so the push/ upload
  doesn't fail halfway. Large build artifacts can cause hangs or blocks.

## Signing (if you add a certificate)

- For the Android APK: keep the release keystore and sign with `apksigner` so updates
  from 2.3.5/2.3.6 install cleanly. Debug-signed APKs with different keys block
  upgrades.
- For Windows: a proper Authenticode signature helps the exe look trusted online.

## Keep the native Windows path healthy

- Rebuild the exe from `app.py` when app or template changes land.
- Re-zip it into `static/releases/` with the matching version name so the downloads
  page picks it up as available.
- Run a quick smoke test (launch exe, hit `/api/version`) before releasing.

## Link to the running site

- Live site: **https://la-maliva-vista-hotel.onrender.com**
- Native Windows downloads are served from the site's `static/releases/` folder and
  shown on the downloads page.
