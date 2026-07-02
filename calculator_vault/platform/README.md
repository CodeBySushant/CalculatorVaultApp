# Platform integration

The `android/` and `ios/` folders are generated locally by `flutter create .`
(see the root README). The files here are the small native additions the app
needs; copy them in once after generating the platform folders.

## Android — FLAG_SECURE (required)

Replace the generated MainActivity with `platform/android/MainActivity.kt`:

```bash
# after: flutter create . --platforms=android,ios --org com.codebysushant
cp platform/android/MainActivity.kt \
   android/app/src/main/kotlin/com/codebysushant/calculator_vault/MainActivity.kt
```

If you used a different `--org` or app name, keep the generated file's
`package ...` line and copy the class body instead.

What it does: while the vault session is active, the Dart side calls
`enable` on the `calculator_vault/secure_screen` channel, which sets
`FLAG_SECURE` — screenshots are blocked and the recents-screen preview is
blank. Leaving the vault calls `disable`, so the plain calculator behaves
like any normal app.

## iOS

No native code file needed, but add these keys to `ios/Runner/Info.plist`
(image_picker uses the photo library and, if you add camera capture later,
the camera):

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Add your photos to the encrypted vault.</string>
<key>NSCameraUsageDescription</key>
<string>Capture photos directly into the encrypted vault.</string>
```

iOS has no FLAG_SECURE equivalent; the Dart-side `PrivacyShield` covers the
app the moment it resigns active, which is what the app switcher snapshot
captures.

### Android

`image_picker` uses the system **Photo Picker** on Android 13+ (API 33+),
which requires **no** runtime storage/media permission. Nothing to add for
photo import. This is a deliberate choice to keep the vault from ever
requesting broad media access.

Documented limitation: iOS cannot programmatically block a user-initiated
screenshot while the app is in the foreground. This is a platform
restriction that applies to all iOS apps.
