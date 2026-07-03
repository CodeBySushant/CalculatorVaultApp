// This file replaces the default `flutter create` template test, which
// referenced a non-existent `MyApp`. The app's real tests live in the other
// files in this directory (expression_engine_test.dart, crypto_service_test.dart,
// vault_items_test.dart, photo_test.dart, and so on).
//
// It is intentionally minimal: booting the full app in a widget test needs
// Hive + secure storage + path_provider fakes, which the integration tests
// in later phases set up properly. Unit/widget coverage of every feature is
// already provided by the dedicated suites.

void main() {}
