import 'package:flutter_test/flutter_test.dart';
import 'package:fletchpdf/features/organize/services/pdf_nup_geometry.dart';

void main() {
  group('PdfNupGeometry.gridFor', () {
    test('uses horizontal 2-up grid for landscape sheets', () {
      final grid = PdfNupGeometry.gridFor(
        pagesPerSheet: 2,
        landscape: true,
      );

      expect(grid.columns, 2);
      expect(grid.rows, 1);
      expect(grid.capacity, 2);
    });

    test('uses vertical 2-up grid for portrait sheets', () {
      final grid = PdfNupGeometry.gridFor(
        pagesPerSheet: 2,
        landscape: false,
      );

      expect(grid.columns, 1);
      expect(grid.rows, 2);
    });

    test('supports 4, 6 and 9 pages per sheet', () {
      expect(
        PdfNupGeometry.gridFor(pagesPerSheet: 4, landscape: true).capacity,
        4,
      );
      expect(
        PdfNupGeometry.gridFor(pagesPerSheet: 6, landscape: false).capacity,
        6,
      );
      expect(
        PdfNupGeometry.gridFor(pagesPerSheet: 9, landscape: true).capacity,
        9,
      );
    });

    test('rejects unsupported layouts', () {
      expect(
        () => PdfNupGeometry.gridFor(
          pagesPerSheet: 3,
          landscape: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PdfNupGeometry.layout', () {
    test('keeps cells inside paper and applies margins and spacing', () {
      final cells = PdfNupGeometry.layout(
        paperWidthMm: 210,
        paperHeightMm: 297,
        columns: 2,
        rows: 2,
        marginMm: 10,
        spacingMm: 4,
      );

      expect(cells, hasLength(4));
      final margin = 10 * PdfNupGeometry.pointsPerMillimeter;
      final gap = 4 * PdfNupGeometry.pointsPerMillimeter;
      expect(cells.first.left, closeTo(margin, 0.001));
      expect(cells.first.top, lessThan(297 * PdfNupGeometry.pointsPerMillimeter));
      expect(cells[1].left - cells[0].right, closeTo(gap, 0.001));
      expect(cells[2].top, lessThan(cells[0].bottom));
      for (final cell in cells) {
        expect(cell.left, greaterThanOrEqualTo(margin - 0.001));
        expect(cell.bottom, greaterThanOrEqualTo(margin - 0.001));
        expect(
          cell.right,
          lessThanOrEqualTo(200 * PdfNupGeometry.pointsPerMillimeter + 0.001),
        );
        expect(
          cell.top,
          lessThanOrEqualTo(287 * PdfNupGeometry.pointsPerMillimeter + 0.001),
        );
      }
    });

    test('rejects margins that leave no usable page area', () {
      expect(
        () => PdfNupGeometry.layout(
          paperWidthMm: 210,
          paperHeightMm: 297,
          columns: 3,
          rows: 3,
          marginMm: 100,
          spacingMm: 10,
        ),
        throwsArgumentError,
      );
    });
  });
}
