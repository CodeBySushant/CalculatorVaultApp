# Play Store Release Checklist — Calculator Vault

## One-time setup (do these once, keep forever)

- [ ] Generate the upload keystore (from the `android/` folder):
      `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
      Back it up somewhere safe (password manager + offline copy).
- [ ] Copy `android/key.properties.example` → `android/key.properties`, fill in real passwords.
      Verify both `key.properties` and `*.jks` are gitignored (they are in the stock Flutter android/.gitignore — confirm).
- [ ] Host `PRIVACY_POLICY.md` at a public URL (GitHub Pages works) and put your real support email in it.
- [ ] Play Console: create the app, enroll in **Play App Signing**.

## Every release

- [ ] Bump `version:` in pubspec.yaml (the `+N` versionCode must always increase).
- [ ] `flutter pub get` → commit the updated `pubspec.lock`.
- [ ] `dart format . && flutter analyze && flutter test` — all green.
- [ ] `flutter build appbundle --release`
- [ ] Test the RELEASE build on a real device before uploading:
      `flutter install --release` — specifically verify:
      - [ ] Fonts render as Manrope/Inter (not system fonts)
      - [ ] Biometric unlock prompt appears and works
      - [ ] Screenshots blocked inside the vault (FLAG_SECURE)
      - [ ] 5 wrong PINs in the calculator → correct PIN silently ignored until cooldown ends; lock screen shows countdown; force-killing the app does NOT reset it
      - [ ] Launcher shows "Calculator" with the new icon
- [ ] Upload `build/app/outputs/bundle/release/app-release.aab` to the **Internal testing** track first.

## Play Console forms

- [ ] **Data safety**: No data collected · No data shared · Data encrypted at rest · No account needed.
- [ ] **Privacy policy URL**: the hosted PRIVACY_POLICY.md.
- [ ] **Content rating** questionnaire (Utility).
- [ ] **Store listing**: Under Google's Misrepresentation/Deceptive Behavior policies the listing must
      honestly describe BOTH functions — e.g. "Calculator with a private, encrypted photo & document vault."
      Never list it as only a calculator. Screenshots should show the vault.
- [ ] **App icon 512px**: use `store_assets/play_store_icon_512.png`.
- [ ] Target audience: 18+ / not designed for children (avoids Families policy overhead).

## Post-launch (Phases 10–12)

- [ ] Notes & Passwords editors, then re-enable their tiles in `vault_home_screen.dart`.
- [ ] Settings screen (auto-lock timeout picker writes `keyAutoLockSeconds`, theme, biometrics toggle, change PIN entry point).
- [ ] Consider `cryptography_flutter` for hardware-accelerated AES if large video imports feel slow.
