import 'package:fletchpdf/features/organize/services/pdf_split_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageRangeParser', () {
    test('parses several page groups', () {
      final result = PageRangeParser.parseGroups(
        '1-3; 4, 6; 7-9',
        pageCount: 10,
      );

      expect(
        result,
        [
          [1, 2, 3],
          [4, 6],
          [7, 8, 9],
        ],
      );
    });

    test('supports individual pages and ranges in one group', () {
      final result = PageRangeParser.parseGroups(
        '1, 3-5, 8; 2, 6-7',
        pageCount: 8,
      );

      expect(
        result,
        [
          [1, 3, 4, 5, 8],
          [2, 6, 7],
        ],
      );
    });

    test('rejects a single group because split needs at least two files', () {
      expect(
        () => PageRangeParser.parseGroups('1-5', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects empty groups', () {
      expect(
        () => PageRangeParser.parseGroups('1-2;;4-5', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects malformed ranges', () {
      expect(
        () => PageRangeParser.parseGroups('1-a; 3-4', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects descending ranges', () {
      expect(
        () => PageRangeParser.parseGroups('4-2; 5-6', pageCount: 6),
        throwsFormatException,
      );
    });

    test('rejects page numbers outside the document', () {
      expect(
        () => PageRangeParser.parseGroups('1-3; 4-8', pageCount: 7),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects duplicate pages across groups', () {
      expect(
        () => PageRangeParser.parseGroups('1-3; 3-5', pageCount: 5),
        throwsFormatException,
      );
    });

    test('rejects duplicate pages inside a group', () {
      expect(
        () => PageRangeParser.parseGroups('1, 2, 2; 3-4', pageCount: 4),
        throwsFormatException,
      );
    });
  });
}
