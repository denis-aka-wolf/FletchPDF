/// Page imposition and sheet geometry for a printable folded booklet.
class PdfBookletGeometry {
  const PdfBookletGeometry._();

  static const double pointsPerMillimeter = 72 / 25.4;

  /// Returns physical sheets in print order. Page indices are zero-based;
  /// null represents a deliberately inserted blank page.
  static List<PdfBookletSheet> impose({
    required int pageCount,
    bool rightBinding = false,
  }) {
    if (pageCount < 1) {
      throw ArgumentError('В документе должна быть хотя бы одна страница.');
    }

    final paddedCount = ((pageCount + 3) ~/ 4) * 4;
    final sheetCount = paddedCount ~/ 4;
    final sheets = <PdfBookletSheet>[];

    for (var index = 0; index < sheetCount; index++) {
      final frontLeft = paddedCount - index * 2;
      final frontRight = index * 2 + 1;
      final backLeft = index * 2 + 2;
      final backRight = paddedCount - index * 2 - 1;

      int? pageIndex(int pageNumber) =>
          pageNumber <= pageCount ? pageNumber - 1 : null;

      var front = PdfBookletSide(
        leftPageIndex: pageIndex(frontLeft),
        rightPageIndex: pageIndex(frontRight),
      );
      var back = PdfBookletSide(
        leftPageIndex: pageIndex(backLeft),
        rightPageIndex: pageIndex(backRight),
      );

      if (rightBinding) {
        front = front.reversed;
        back = back.reversed;
      }

      sheets.add(PdfBookletSheet(front: front, back: back));
    }
    return List.unmodifiable(sheets);
  }

  /// Creates two equal portrait page cells on a landscape paper sheet.
  static List<PdfBookletCell> layout({
    required double paperWidthMm,
    required double paperHeightMm,
    required double marginMm,
    required double gutterMm,
  }) {
    _requirePositive(paperWidthMm, 'Ширина листа');
    _requirePositive(paperHeightMm, 'Высота листа');
    if (!marginMm.isFinite || marginMm < 0 ||
        !gutterMm.isFinite || gutterMm < 0) {
      throw ArgumentError('Поля и центральный отступ не могут быть отрицательными.');
    }
    final availableWidth = paperWidthMm - marginMm * 2 - gutterMm;
    final availableHeight = paperHeightMm - marginMm * 2;
    if (availableWidth <= 0 || availableHeight <= 0) {
      throw ArgumentError('Поля и центральный отступ слишком велики для листа.');
    }

    final cellWidth = availableWidth / 2;
    final left = marginMm * pointsPerMillimeter;
    final bottom = marginMm * pointsPerMillimeter;
    final height = availableHeight * pointsPerMillimeter;
    final width = cellWidth * pointsPerMillimeter;
    final gap = gutterMm * pointsPerMillimeter;

    return List.unmodifiable([
      PdfBookletCell(left: left, bottom: bottom, width: width, height: height),
      PdfBookletCell(
        left: left + width + gap,
        bottom: bottom,
        width: width,
        height: height,
      ),
    ]);
  }

  static void _requirePositive(double value, String label) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('$label должна быть больше нуля.');
    }
  }
}

class PdfBookletSide {
  const PdfBookletSide({
    required this.leftPageIndex,
    required this.rightPageIndex,
  });

  final int? leftPageIndex;
  final int? rightPageIndex;

  PdfBookletSide get reversed => PdfBookletSide(
        leftPageIndex: rightPageIndex,
        rightPageIndex: leftPageIndex,
      );
}

class PdfBookletSheet {
  const PdfBookletSheet({required this.front, required this.back});

  final PdfBookletSide front;
  final PdfBookletSide back;
}

class PdfBookletCell {
  const PdfBookletCell({
    required this.left,
    required this.bottom,
    required this.width,
    required this.height,
  });

  final double left;
  final double bottom;
  final double width;
  final double height;
}
