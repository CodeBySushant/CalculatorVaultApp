import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/application/vault_session.dart';
import '../../features/authentication/presentation/change_pin_screen.dart';
import '../../features/authentication/presentation/lock_screen.dart';
import '../../features/authentication/presentation/pin_setup_screen.dart';
import '../../features/calculator/presentation/calculator_screen.dart';
import '../../features/documents/presentation/document_list_screen.dart';
import '../../features/documents/presentation/document_viewer_screen.dart';
import '../../features/photos/presentation/photo_grid_screen.dart';
import '../../features/photos/presentation/photo_viewer_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/videos/presentation/video_grid_screen.dart';
import '../../features/videos/presentation/video_player_screen.dart';
import '../../features/vault/domain/vault_item.dart';
import '../../features/vault/presentation/trash_screen.dart';
import '../../features/vault/presentation/vault_home_screen.dart';
import '../../features/vault/presentation/vault_item_list_screen.dart';
import '../../features/vault/presentation/vault_shell.dart';

/// Named routes. Every navigation call uses these — never raw strings.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String calculator = '/calculator';
  static const String setup = '/setup';
  static const String lock = '/lock';
  static const String vault = '/vault';
  static const String vaultFavorites = '/vault/favorites';
  static const String vaultTrash = '/vault/trash';
  static const String photoViewer = '/vault/photo-viewer';
  static const String videoPlayer = '/vault/video-player';
  static const String documentViewer = '/vault/document-viewer';
  static const String changePin = '/vault/change-pin';
  static const String resetPin = '/reset-pin';

  /// Category list route for a [VaultItemType].
  static String vaultItems(VaultItemType type) => '/vault/items/${type.name}';
}

/// Bridges Riverpod session changes into GoRouter's refreshListenable so
/// redirects re-evaluate the moment the vault locks or unlocks.
class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final _routerRefreshProvider = Provider<_RouterRefresh>((ref) {
  final _RouterRefresh refresh = _RouterRefresh();
  ref.listen<VaultSessionState>(
    vaultSessionProvider,
    (VaultSessionState? _, VaultSessionState __) => refresh.refresh(),
  );
  ref.onDispose(refresh.dispose);
  return refresh;
});

/// App-wide router provider.
///
/// Guard rules:
/// - Vault routes require an unlocked session. A locked session goes to the
///   lock screen; a session that was never unlocked goes to the calculator,
///   so the lock screen (which reveals the vault exists) can only ever
///   appear mid-session.
/// - The reset-PIN route additionally requires recovery-key verification,
///   signalled via `extra: true` from the lock screen.
final appRouterProvider = Provider<GoRouter>((ref) {
  final _RouterRefresh refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refresh,
    redirect: (context, state) {
      final VaultSessionState session = ref.read(vaultSessionProvider);
      final String location = state.matchedLocation;

      final bool needsUnlock = location.startsWith(AppRoutes.vault);
      if (needsUnlock && session != VaultSessionState.unlocked) {
        return session == VaultSessionState.locked
            ? AppRoutes.lock
            : AppRoutes.calculator;
      }
      if (location == AppRoutes.lock) {
        if (session == VaultSessionState.unlocked) return AppRoutes.vault;
        if (session == VaultSessionState.none) return AppRoutes.calculator;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.calculator,
        name: 'calculator',
        builder: (context, state) => const CalculatorScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        name: 'setup',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        name: 'lock',
        builder: (context, state) => const LockScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => VaultShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.vault,
            name: 'vault',
            builder: (context, state) => const VaultHomeScreen(),
          ),
          GoRoute(
            path: '/vault/items/:type',
            name: 'vaultItems',
            redirect: (context, state) {
              final String? raw = state.pathParameters['type'];
              final bool valid =
                  VaultItemType.values.any((VaultItemType t) => t.name == raw);
              return valid ? null : AppRoutes.vault;
            },
            builder: (context, state) {
              final VaultItemType type =
                  VaultItemType.values.byName(state.pathParameters['type']!);
              return switch (type) {
                VaultItemType.photo => const PhotoGridScreen(),
                VaultItemType.video => const VideoGridScreen(),
                VaultItemType.document => const DocumentListScreen(),
                _ => VaultItemListScreen.category(type),
              };
            },
          ),
          GoRoute(
            path: AppRoutes.vaultFavorites,
            name: 'vaultFavorites',
            builder: (context, state) => const VaultItemListScreen.favorites(),
          ),
          GoRoute(
            path: AppRoutes.vaultTrash,
            name: 'vaultTrash',
            builder: (context, state) => const TrashScreen(),
          ),
          GoRoute(
            path: AppRoutes.photoViewer,
            name: 'photoViewer',
            redirect: (context, state) =>
                state.extra is PhotoViewerArgs ? null : AppRoutes.vault,
            builder: (context, state) => PhotoViewerScreen(
              args: state.extra! as PhotoViewerArgs,
            ),
          ),
          GoRoute(
            path: AppRoutes.videoPlayer,
            name: 'videoPlayer',
            redirect: (context, state) =>
                state.extra is VideoPlayerArgs ? null : AppRoutes.vault,
            builder: (context, state) => VideoPlayerScreen(
              args: state.extra! as VideoPlayerArgs,
            ),
          ),
          GoRoute(
            path: AppRoutes.documentViewer,
            name: 'documentViewer',
            redirect: (context, state) =>
                state.extra is DocumentViewerArgs ? null : AppRoutes.vault,
            builder: (context, state) => DocumentViewerScreen(
              args: state.extra! as DocumentViewerArgs,
            ),
          ),
          GoRoute(
            path: AppRoutes.changePin,
            name: 'changePin',
            builder: (context, state) =>
                const ChangePinScreen(requireCurrent: true),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.resetPin,
        name: 'resetPin',
        redirect: (context, state) =>
            state.extra == true ? null : AppRoutes.calculator,
        builder: (context, state) =>
            const ChangePinScreen(requireCurrent: false),
      ),
    ],
  );
});
