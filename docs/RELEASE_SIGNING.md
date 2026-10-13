# Release signing — La-Maliva Vista Android app

The Android APK is **store-signed** whenever the signing materials are present; otherwise
the Flutter default (debug keystore) is used so local `flutter run --release` keeps working.

## Where things live (never commit the real ones)

| File | Purpose | Committed? |
|---|---|---|
| `mobile_app/android/la-maliva-release.jks` | THE release keystore (RSA 2048, alias `lamaliva`, validity 10 000 days) | ❌ gitignored |
| `mobile_app/android/key.properties` | Points Gradle at the keystore + passwords | ❌ gitignored |
| `mobile_app/android/key.properties.example` | Template showing the required keys | ✅ committed |
| GitHub repo secrets | `APK_KEYSTORE_BASE64`, `APK_KEYSTORE_PASSWORD`, `APK_KEY_PASSWORD` | (GitHub-side) |

## How CI signs builds

`.github/workflows/build-release.yml` restores the keystore from the repo secrets
before `flutter build apk --release`, so every tagged release (`v*`) ships an APK
signed with the same key — updates install over previous versions without forcing
an uninstall.

## Local release build

```bash
cd mobile_app/android
cp key.properties.example key.properties   # then fill real passwords
keytool -genkeypair ...                    # or restore your backup of the .jks
cd ..
flutter build apk --release
```

## ⚠️ Backup — this is important

The keystore IS the app's identity on device. If it is lost, new APKs can only be
installed after uninstalling the old app (guests lose their cached data).

Keep **both** of these safe:
1. `mobile_app/android/la-maliva-release.jks` (the file itself)
2. The keystore password (also recoverable from the GitHub secret
   `APK_KEYSTORE_PASSWORD` by a repo admin).

Recommended: store a copy of the `.jks` outside this computer (e.g. the hotel's
cloud drive).
