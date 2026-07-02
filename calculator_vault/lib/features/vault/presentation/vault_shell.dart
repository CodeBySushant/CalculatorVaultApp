import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/vault_session.dart';

/// Wraps every vault-area route. Any pointer interaction resets the
/// auto-lock idle timer, so individual screens never have to remember to.
class VaultShell extends ConsumerWidget {
  const VaultShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(vaultSessionProvider.notifier).touch(),
      child: child,
    );
  }
}
