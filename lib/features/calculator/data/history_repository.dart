import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/services/hive_service.dart';
import '../domain/history_entry.dart';

/// Contract for calculator history persistence.
abstract interface class CalcHistoryRepository {
  /// Adds an entry, evicting the oldest ones beyond [maxEntries].
  Future<void> add(HistoryEntry entry);

  /// All entries, newest first.
  List<HistoryEntry> all();

  /// Deletes every entry.
  Future<void> clear();

  static const int maxEntries = 100;
}

/// Riverpod provider — overridden with an in-memory fake in tests.
final calcHistoryRepositoryProvider = Provider<CalcHistoryRepository>(
  (ref) => HiveCalcHistoryRepository(ref.watch(hiveServiceProvider)),
);

/// Hive-backed implementation. History is calculation math only (never PIN
/// attempts — the controller skips history for pure digit entries).
class HiveCalcHistoryRepository implements CalcHistoryRepository {
  HiveCalcHistoryRepository(this._hive);

  final HiveService _hive;

  Box<dynamic> get _box => _hive.calcHistory;

  @override
  Future<void> add(HistoryEntry entry) async {
    await _box.add(entry.toMap());
    while (_box.length > CalcHistoryRepository.maxEntries) {
      await _box.deleteAt(0);
    }
  }

  @override
  List<HistoryEntry> all() {
    final List<HistoryEntry> entries = _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(HistoryEntry.fromMap)
        .toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  @override
  Future<void> clear() => _box.clear();
}
