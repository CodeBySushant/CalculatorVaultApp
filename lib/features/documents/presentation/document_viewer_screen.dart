import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/shared.dart';
import '../../authentication/application/vault_session.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../application/document_providers.dart';
import '../data/document_types.dart';

/// Arguments for the document viewer route.
class DocumentViewerArgs {
  const DocumentViewerArgs({required this.itemId});
  final String itemId;
}

/// Views a vault document. Images, text, and PDFs render fully in-app
/// (PDFs from decrypted bytes in memory — no plaintext temp file). Other
/// formats open in the system viewer via a temp copy that is wiped when
/// the vault locks.
class DocumentViewerScreen extends ConsumerWidget {
  const DocumentViewerScreen({super.key, required this.args});

  final DocumentViewerArgs args;

  VaultItem? _item(WidgetRef ref) {
    for (final VaultItem i in ref.watch(documentItemsProvider)) {
      if (i.id == args.itemId) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VaultItem? item = _item(ref);
    if (item == null || item.relativePath == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Symbols.error,
          title: 'Document unavailable',
          message: 'This document could not be opened.',
        ),
      );
    }

    final DocumentKind kind = documentKindFor(item.name, item.mimeType);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Open externally',
            icon: const Icon(Symbols.open_in_new),
            onPressed: () => _openExternally(context, ref, item),
          ),
          IconButton(
            tooltip: 'Move to trash',
            icon: const Icon(Symbols.delete),
            onPressed: () => _delete(context, ref, item),
          ),
        ],
      ),
      body: switch (kind) {
        DocumentKind.image => _ImageBody(relativePath: item.relativePath!),
        DocumentKind.text => _TextBody(relativePath: item.relativePath!),
        DocumentKind.pdf => _PdfBody(item: item),
        DocumentKind.other => _ExternalBody(
            item: item,
            onOpen: () => _openExternally(context, ref, item),
          ),
      },
    );
  }

  Future<void> _openExternally(
    BuildContext context,
    WidgetRef ref,
    VaultItem item,
  ) async {
    final String ext =
        item.name.contains('.') ? item.name.split('.').last : 'bin';
    try {
      final file =
          await ref.read(vaultSessionProvider.notifier).withoutAutoLock(
                () => ref
                    .read(vaultFileStoreProvider)
                    .decryptToTempFile(item.relativePath!, extension: ext),
              );
      await ref.read(vaultSessionProvider.notifier).withoutAutoLock(
            () => Share.shareXFiles(<XFile>[XFile(file.path, name: item.name)]),
          );
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this document'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    VaultItem item,
  ) async {
    await ref.read(vaultItemsProvider.notifier).moveToTrash(<String>[item.id]);
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Moved to trash'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(vaultItemsProvider.notifier).restore(<String>[item.id]),
        ),
      ),
    );
  }
}

class _ImageBody extends ConsumerWidget {
  const _ImageBody({required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List> bytes =
        ref.watch(documentBytesProvider(relativePath));
    return bytes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: Symbols.broken_image,
        title: 'Could not load image',
        message: 'The image data could not be decrypted.',
      ),
      data: (Uint8List data) => InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: Image.memory(data)),
      ),
    );
  }
}

class _TextBody extends ConsumerWidget {
  const _TextBody({required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<String> text =
        ref.watch(documentTextProvider(relativePath));
    return text.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: Symbols.error,
        title: 'Could not load text',
        message: 'The document could not be decrypted.',
      ),
      data: (String content) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SelectableText(
          content.isEmpty ? '(empty file)' : content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// In-app PDF viewer. Decrypted bytes are handed to pdfrx in memory —
/// nothing is ever written to disk in plaintext for viewing. Supports
/// pinch-zoom, paging, and shows the current page in an overlay.
class _PdfBody extends ConsumerStatefulWidget {
  const _PdfBody({required this.item});

  final VaultItem item;

  @override
  ConsumerState<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends ConsumerState<_PdfBody> {
  final PdfViewerController _controller = PdfViewerController();
  int _page = 1;
  int _pageCount = 0;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Uint8List> bytes =
        ref.watch(documentBytesProvider(widget.item.relativePath!));
    final ThemeData theme = Theme.of(context);

    return bytes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: Symbols.picture_as_pdf,
        title: 'Could not load PDF',
        message: 'The document could not be decrypted.',
      ),
      data: (Uint8List data) => Stack(
        children: <Widget>[
          PdfViewer.data(
            data,
            sourceName: widget.item.name,
            controller: _controller,
            params: PdfViewerParams(
              backgroundColor: theme.colorScheme.surface,
              maxScale: 8,
              onViewerReady: (PdfDocument document, PdfViewerController _) {
                if (mounted) {
                  setState(() => _pageCount = document.pages.length);
                }
              },
              onPageChanged: (int? pageNumber) {
                if (mounted && pageNumber != null) {
                  setState(() => _page = pageNumber);
                }
              },
              errorBannerBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace, PdfDocumentRef documentRef) =>
                  const EmptyState(
                icon: Symbols.picture_as_pdf,
                title: 'Could not render PDF',
                message:
                    'This file may be corrupted or password-protected.',
              ),
            ),
          ),
          if (_pageCount > 0)
            Positioned(
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.85),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    '$_page / $_pageCount',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExternalBody extends StatelessWidget {
  const _ExternalBody({required this.item, required this.onOpen});

  final VaultItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint) = documentVisual(item.name);
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: AppRadius.lgAll,
              ),
              child: Icon(icon, size: 44, color: tint),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              item.name,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              Formatters.bytes(item.byteLength),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Preview for this file type opens in another app. Your '
              'document is decrypted only temporarily and wiped when the '
              'vault locks.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Open',
              icon: Symbols.open_in_new,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
