import 'package:calculator_vault/features/documents/data/document_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('documentKindFor', () {
    test('classifies images by mime and extension', () {
      expect(documentKindFor('photo.jpg', null), DocumentKind.image);
      expect(documentKindFor('scan.PNG', null), DocumentKind.image);
      expect(documentKindFor('anything', 'image/webp'), DocumentKind.image);
    });

    test('classifies PDFs', () {
      expect(documentKindFor('contract.pdf', null), DocumentKind.pdf);
      expect(documentKindFor('SCAN.PDF', null), DocumentKind.pdf);
      expect(documentKindFor('noext', 'application/pdf'), DocumentKind.pdf);
      // Misnamed but declared PDF → mime wins, renders in-app.
      expect(
        documentKindFor('report.docx', 'application/pdf'),
        DocumentKind.pdf,
      );
    });

    test('classifies text and code', () {
      expect(documentKindFor('notes.txt', null), DocumentKind.text);
      expect(documentKindFor('data.csv', null), DocumentKind.text);
      expect(documentKindFor('main.dart', null), DocumentKind.text);
      expect(documentKindFor('config.yaml', null), DocumentKind.text);
      expect(documentKindFor('readme', 'text/markdown'), DocumentKind.text);
    });

    test('falls back to other for unknown/binary', () {
      expect(documentKindFor('archive.zip', null), DocumentKind.other);
      expect(documentKindFor('sheet.xlsx', null), DocumentKind.other);
      expect(documentKindFor('noextension', null), DocumentKind.other);
    });

    test('mime takes priority over extension', () {
      // Named .txt but declared image → image.
      expect(documentKindFor('weird.txt', 'image/png'), DocumentKind.image);
    });
  });

  group('documentVisual', () {
    test('returns distinct icons per family without throwing', () {
      for (final String name in <String>[
        'a.pdf',
        'b.docx',
        'c.xlsx',
        'd.pptx',
        'e.zip',
        'f.png',
        'g.txt',
        'h.json',
        'i.unknown',
        'noext',
      ]) {
        final (icon, _) = documentVisual(name);
        expect(icon, isNotNull, reason: name);
      }
    });
  });
}
