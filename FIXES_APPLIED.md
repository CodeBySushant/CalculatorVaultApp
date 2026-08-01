# What this fix pack changes (overwrite into project root)

| # | Fix | Files |
|---|-----|-------|
| 1 | Release signing via key.properties (debug fallback for local runs only) | android/app/build.gradle.kts, android/key.properties.example |
| 2 | Release AAB CI pipeline for Play Store | .github/workflows/release-aab.yml |
| 3 | Launcher label "Calculator" (was calculator_vault) | android/app/src/main/AndroidManifest.xml |
| 4 | Real calculator icon: adaptive + legacy + 512px store icon | android/app/src/main/res/mipmap-*, store_assets/ |
| 5 | Biometrics fixed: FlutterFragmentActivity + USE_BIOMETRIC permission | MainActivity.kt, AndroidManifest.xml |
| 6 | Fonts bundled offline (google_fonts removed) | assets/fonts/, pubspec.yaml, lib/shared/theme/app_typography.dart |
| 7 | Auto Backup/device transfer disabled (prevents undecryptable restores) | AndroidManifest.xml, res/xml/data_extraction_rules.xml |
| 8+9 | Persisted, escalating brute-force guard shared by calculator + lock screen | pin_attempt_guard.dart (new), app_constants.dart, calculator_controller.dart, lock_screen.dart |
| 10 | iOS: NSFaceIDUsageDescription + display name "Calculator" | ios/Runner/Info.plist |
| 11 | targetSdk pinned to 35 (Play requirement) | android/app/build.gradle.kts |
| 12 | Plugin compileSdk 36 alignment block (file_picker) | android/build.gradle.kts |
| 13 | Privacy policy template + full Play Console checklist | PRIVACY_POLICY.md, RELEASE_CHECKLIST.md |
| 14 | Unfinished Notes/Passwords tiles hidden for v1 | lib/features/vault/presentation/vault_home_screen.dart |
| 15 | R8 minify + shrinkResources + proguard file | android/app/build.gradle.kts, android/app/proguard-rules.pro |
| 16 | Tests updated + new brute-force coverage | test/calculator_controller_test.dart |
| 17 | README corrected (platform folders, security model, getting started) | README.md |
| 18 | Version bumped to 1.0.0+1 | pubspec.yaml |

Manual steps remaining: delete analyze_output.txt, generate keystore, fill key.properties,
host the privacy policy, commit pubspec.lock. See RELEASE_CHECKLIST.md.
