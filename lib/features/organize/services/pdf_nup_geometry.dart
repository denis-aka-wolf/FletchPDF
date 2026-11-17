import 'dart:math' as math;

/// Physical dimensions and grid geometry for a PDF N-up sheet.
class PdfNupGeometry {
  const PdfNupGeometry._();

  static const double pointsPerMillimeter = 72 / 25.4;

  static PdfNupGrid gridFor({
    required int pagesPerSheet,
    required bool landscape,
  }) {
    return switch (pagesPerSheet) {
      2 => landscape
          ? const PdfNupGrid(columns: 2, rows: 1)
          : const PdfNupGrid(columns: 1, rows: 2),
      4 => const PdfNupGrid(columns: 2, rows: 2),
      6 => landscape
          ? const PdfNupGrid(columns: 3, rows: 2)
          : const PdfNupGrid(columns: 2, rows: 3),
      9 => const PdfNupGrid(columns: 3, rows: 3),
      _ => throw ArgumentError('Поддерживаются варианты 2, 4, 6 или 9 страниц на листе.'),
    };
  }

  static List<PdfNupCell> layout({
    required double paperWidthMm,
    required double paperHeightMm,
    required int columns,
    required int rows,
    required double marginMm,
    required double spacingMm,
  }) {
    _requirePositive(paperWidthMm, 'Ширина листа');
    _requirePositive(paperHeightMm, 'Высота листа');
    if (columns < 1 || rows < 1) {
      throw ArgumentError('Количество столбцов и строк должно быть положительным.');
    }
    if (!marginMm.isFinite || marginMm < 0 ||
        !spacingMm.isFinite || spacingMm < 0) {
      throw ArgumentError('Поля и промежутки не могут быть отрицательными.');
    }

    final availableWidth =
        paperWidthMm - marginMm * 2 - spacingMm * (columns - 1);
    final availableHeight =
        paperHeightMm - marginMm * 2 - spacingMm * (rows - 1);
    if (availableWidth <= 0 || availableHeight <= 0) {
      throw ArgumentError('Поля и промежутки слишком велики для выбранного листа.');
    }

    final cellWidth = availableWidth / columns;
    final cellHeight = availableHeight / rows;
    final result = <PdfNupCell>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final leftMm = marginMm + column * (cellWidth + spacingMm);
        final topMm = marginMm + row * (cellHeight + spacingMm);
        result.add(PdfNupCell(
          left: leftMm * pointsPerMillimeter,
          bottom: (paperHeightMm - topMm - cellHeight) *
              pointsPerMillimeter,
          right: (leftMm + cellWidth) * pointsPerMillimeter,
          top: (paperHeightMm - topMm) * pointsPerMillimeter,
        ));
      }
    }
    return List.unmodifiable(result);
  }

  static void _requirePositive(double value, String label) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('$label должна быть больше нуля.');
    }
  }
}

class PdfNupGrid {
  const PdfNupGrid({required this.columns, required this.rows});

  final int columns;
  final int rows;

  int get capacity => columns * rows;
}

class PdfNupCell {
  const PdfNupCell({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;
}
