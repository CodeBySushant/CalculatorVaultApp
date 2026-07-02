/// A single calculation stored in history.
class HistoryEntry {
  const HistoryEntry({
    required this.expression,
    required this.result,
    required this.timestamp,
  });

  factory HistoryEntry.fromMap(Map<dynamic, dynamic> map) {
    return HistoryEntry(
      expression: map['e'] as String,
      result: map['r'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['t'] as int),
    );
  }

  final String expression;
  final String result;
  final DateTime timestamp;

  Map<String, Object> toMap() => <String, Object>{
        'e': expression,
        'r': result,
        't': timestamp.millisecondsSinceEpoch,
      };
}
