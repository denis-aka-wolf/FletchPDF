import 'package:flutter_test/flutter_test.dart';
import 'package:fletchpdf/features/organize/services/pdf_booklet_geometry.dart';

void main() {
  group('PdfBookletGeometry.impose', () {
    test('imposes an eight-page booklet in correct duplex order', () {
      final sheets = PdfBookletGeometry.impose(pageCount: 8);

      expect(sheets, hasLength(2));
      expect(
        [sheets[0].front.leftPageIndex, sheets[0].front.rightPageIndex],
        [7, 0],
      );
      expect(
        [sheets[0].back.leftPageIndex, sheets[0].back.rightPageIndex],
        [1, 6],
      );
      expect(
        [sheets[1].front.leftPageIndex, sheets[1].front.rightPageIndex],
        [5, 2],
      );
      expect(
        [sheets[1].back.leftPageIndex, sheets[1].back.rightPageIndex],
        [3, 4],
      );
    });

    test('pads a five-page document with three blank pages', () {
      final sheets = PdfBookletGeometry.impose(pageCount: 5);

      expect(sheets, hasLength(2));
      expect(
        [sheets[0].front.leftPageIndex, sheets[0].front.rightPageIndex],
        [null, 0],
      );
      expect(
        [sheets[0].back.leftPageIndex, sheets[0].back.rightPageIndex],
        [1, null],
      );
      expect(
        [sheets[1].front.leftPageIndex, sheets[1].front.rightPageIndex],
        [null, 2],
      );
      expect(
        [sheets[1].back.leftPageIndex, sheets[1].back.rightPageIndex],
        [3, 4],
      );
    });

    test('mirrors page placement for right binding', () {
      final sheets = PdfBookletGeometry.impose(
        pageCount: 4,
        rightBinding: true,
      );

      expect(
        [sheets.single.front.leftPageIndex, sheets.single.front.rightPageIndex],
        [0, 3],
      );
      expect(
        [sheets.single.back.leftPageIndex, sheets.single.back.rightPageIndex],
        [2, 1],
      );
    });

    test('rejects an empty document', () {
      expect(
        () => PdfBookletGeometry.impose(pageCount: 0),
        throwsArgumentError,
      );
    });
  });

  group('PdfBookletGeometry.layout', () {
    test('creates two equal cells with a center gutter', () {
      final cells = PdfBookletGeometry.layout(
        paperWidthMm: 297,
        paperHeightMm: 210,
        marginMm: 8,
        gutterMm: 6,
      );

      expect(cells, hasLength(2));
      expect(cells[0].width, closeTo(cells[1].width, 0.001));
      expect(
        cells[1].left - (cells[0].left + cells[0].width),
        closeTo(6 * PdfBookletGeometry.pointsPerMillimeter, 0.001),
      );
    });

    test('rejects margins that leave no printable area', () {
      expect(
        () => PdfBookletGeometry.layout(
          paperWidthMm: 297,
          paperHeightMm: 210,
          marginMm: 110,
          gutterMm: 80,
        ),
        throwsArgumentError,
      );
    });
  });
}
