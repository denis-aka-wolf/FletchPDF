import 'package:fletchpdf/features/organize/services/pdf_extract_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageSelectionParser', () {
    test('parses individual pages and ranges in requested order', () {
      expect(
        PageSelectionParser.parse('1-3, 5, 8-9', pageCount: 10),
        [1, 2, 3, 5, 8, 9],
      );
    });

    test('preserves a custom page order', () {
      expect(
        PageSelectionParser.parse('5, 1-2, 4', pageCount: 5),
        [5, 1, 2, 4],
      );
    });

    test('rejects empty input and empty elements', () {
      expect(
        () => PageSelectionParser.parse(' ', pageCount: 5),
        throwsFormatException,
      );
      expect(
        () => PageSelectionParser.parse('1-2,,4', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects malformed and descending ranges', () {
      expect(
        () => PageSelectionParser.parse('1-a', pageCount: 5),
        throwsFormatException,
      );
      expect(
        () => PageSelectionParser.parse('4-2', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects pages outside the document', () {
      expect(
        () => PageSelectionParser.parse('1-6', pageCount: 5),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects duplicate pages', () {
      expect(
        () => PageSelectionParser.parse('1-3, 3, 5', pageCount: 5),
        throwsFormatException,
      );
    });
  });
}
