import 'package:intl/intl.dart';

/// Human-readable formatting helpers shared across the vault UI.
abstract final class Formatters {
  static final DateFormat _date = DateFormat.yMMMd();

  /// `1536` → `1.5 KB`, `0` → `—`.
  static String bytes(int bytes) {
    if (bytes <= 0) return '—';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final String number = value >= 10 || unit == 0
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$number ${units[unit]}';
  }

  /// `Jan 4, 2026`.
  static String date(DateTime date) => _date.format(date);

  /// `3:07` or `1:02:07` for longer media.
  static String duration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    final String twoSec = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final String twoMin = minutes.toString().padLeft(2, '0');
      return '$hours:$twoMin:$twoSec';
    }
    return '$minutes:$twoSec';
  }
}
