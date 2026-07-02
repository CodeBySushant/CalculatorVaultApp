import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/app_tokens.dart';
import '../theme/app_colors.dart';

/// Covers the entire app with a neutral branded surface the moment the app
/// stops being the foreground, active window.
///
/// This is what the app switcher / recents preview captures on iOS (which
/// has no FLAG_SECURE) and acts as a second layer on Android. The cover is
/// deliberately calculator-branded — it reveals nothing about the vault.
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  bool _obscure = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool obscure = state != AppLifecycleState.resumed;
    if (obscure != _obscure) {
      setState(() => _obscure = obscure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        IgnorePointer(
          ignoring: !_obscure,
          child: AnimatedOpacity(
            opacity: _obscure ? 1 : 0,
            duration: AppMotion.fast,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: const Icon(
                    Symbols.calculate,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
