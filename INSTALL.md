# Install / build notes — native Windows desktop app

Short note about the native Windows build so the online release stays lean and safe.

## What you get

- A native Flutter Windows desktop app (the same app experience as Android), packaged with its required DLLs and `data/` runtime folder.
- Download the full ZIP from the website or GitHub release; the direct `.exe` link is also available, but the EXE needs those adjacent runtime files in the extracted bundle to launch.

## Why it's kept small

The native Windows build must not be heavy — a big package is hard to download,
slow to update, and more likely to get flagged by SmartScreen or over the site's
bandwidth. The build intentionally:

- Built with `flutter build windows --release` as the native Windows counterpart to the Android Flutter app.
- Packages only the generated release runtime: the app EXE, Flutter engine and plugin DLLs, and `data/flutter_assets`.
- Does **not** include previous release archives, repository source, or development build directories.

## What to do after downloading

1. Download `La-Maliva-Vista-2.3.11-windows.zip`.
2. Extract (right-click → Extract All, or 7-Zip / Windows Explorer).
3. Run `lamaliva_app.exe` from the extracted folder (leave its DLLs and `data/` folder beside it).
4. If Windows SmartScreen warns, choose **More info → Run anyway** (the app is
   unsigned in this build).

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

- Rebuild the app with `flutter build windows --release` when Flutter app changes land.
- Place `La-Maliva-Vista-<version>.exe` and `La-Maliva-Vista-<version>-windows.zip` in `static/releases/`.
- Smoke-test the app EXE from the extracted bundle and verify the direct download links on the website.

## Link to the running site

- Live site: **https://la-maliva-vista-hotel.onrender.com**
- Native Windows downloads are served from the site's `static/releases/` folder and
  shown on the downloads page.
