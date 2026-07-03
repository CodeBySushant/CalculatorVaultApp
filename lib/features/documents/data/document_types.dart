import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../shared/theme/app_colors.dart';

/// How a document should be handled for viewing.
enum DocumentKind {
  /// Rendered in-app with the image viewer.
  image,

  /// Rendered in-app as scrollable text.
  text,

  /// PDF — opened via the system viewer (share/open sheet).
  pdf,

  /// Everything else (Office, archives, unknown) — opened externally.
  other,
}

const Set<String> _imageExt = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
};

const Set<String> _textExt = <String>{
  'txt',
  'md',
  'markdown',
  'csv',
  'tsv',
  'json',
  'log',
  'xml',
  'yaml',
  'yml',
  'html',
  'htm',
  'css',
  'js',
  'ts',
  'dart',
  'py',
  'java',
  'kt',
  'kts',
  'c',
  'cpp',
  'h',
  'hpp',
  'sh',
  'bat',
  'ini',
  'conf',
  'toml',
  'sql',
  'rs',
  'go',
};

/// Classifies a document by mime type (preferred) then file extension.
DocumentKind documentKindFor(String name, String? mime) {
  if (mime != null) {
    if (mime.startsWith('image/')) return DocumentKind.image;
    if (mime == 'application/pdf') return DocumentKind.pdf;
    if (mime.startsWith('text/')) return DocumentKind.text;
  }
  final String ext =
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (_imageExt.contains(ext)) return DocumentKind.image;
  if (ext == 'pdf') return DocumentKind.pdf;
  if (_textExt.contains(ext)) return DocumentKind.text;
  return DocumentKind.other;
}

/// A recognizable icon + tint for a document, based on its extension.
(IconData, Color) documentVisual(String name) {
  final String ext =
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => (Symbols.picture_as_pdf, AppColors.danger),
    'doc' || 'docx' => (Symbols.description, AppColors.royalBlue),
    'xls' || 'xlsx' || 'csv' || 'tsv' => (Symbols.table, AppColors.emerald),
    'ppt' || 'pptx' => (Symbols.slideshow, AppColors.warning),
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => (
        Symbols.folder_zip,
        AppColors.premiumPurple
      ),
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' ||
    'heif' =>
      (Symbols.image, AppColors.cyan),
    'txt' || 'md' || 'markdown' || 'log' || 'rtf' => (
        Symbols.article,
        AppColors.cyan
      ),
    'json' ||
    'xml' ||
    'yaml' ||
    'yml' ||
    'html' ||
    'css' ||
    'js' ||
    'dart' ||
    'py' ||
    'java' ||
    'kt' =>
      (Symbols.code, AppColors.premiumPurple),
    _ => (Symbols.draft, AppColors.deepIndigo),
  };
}
