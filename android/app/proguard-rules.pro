# Flutter and every plugin used here ship consumer ProGuard rules, so this
# file stays minimal. Add app-specific keep rules below if a release build
# ever misbehaves after minification.

# Keep the MethodChannel host activity name stable (referenced from the
# manifest; R8 keeps manifest entries anyway — belt and braces).
-keep class com.codebysushant.calculator_vault.MainActivity { *; }
