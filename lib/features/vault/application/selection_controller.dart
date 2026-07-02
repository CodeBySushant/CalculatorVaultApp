import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Multi-select state for vault item lists. Auto-disposes when the screen
/// using it goes away, so selections never leak between screens.
final selectionProvider =
    NotifierProvider.autoDispose<SelectionController, Set<String>>(
  SelectionController.new,
);

class SelectionController extends AutoDisposeNotifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  bool get isActive => state.isNotEmpty;

  void toggle(String id) {
    final Set<String> next = <String>{...state};
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void selectAll(Iterable<String> ids) {
    state = <String>{...ids};
  }

  void clear() {
    state = const <String>{};
  }
}
