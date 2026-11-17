import 'package:pdfrx/pdfrx.dart';

/// A crop rectangle expressed as fractions of the currently visible page.
///
/// Coordinates use a top-left origin: left/top are inclusive edges and
/// right/bottom are exclusive edges. Every value must be in the 0..1 range.
class NormalizedCropRect {
  const NormalizedCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const NormalizedCropRect.full()
      : left = 0,
        top = 0,
        right = 1,
        bottom = 1;

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isFull =>
      left <= 0 && top <= 0 && right >= 1 && bottom >= 1;

  void validate() {
    if (![left, top, right, bottom].every((value) => value.isFinite)) {
      throw ArgumentError('Координаты области обрезки должны быть конечными числами.');
    }
    if (left < 0 || top < 0 || right > 1 || bottom > 1 ||
        left >= right || top >= bottom) {
      throw ArgumentError('Область обрезки должна находиться внутри страницы и иметь ненулевой размер.');
    }
  }
}

/// PDF page rectangle in native PDF coordinates (origin at bottom-left).
class PdfCropBounds {
  const PdfCropBounds({
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

  void validate() {
    if (![left, bottom, right, top].every((value) => value.isFinite) ||
        width <= 0 ||
        height <= 0) {
      throw ArgumentError('PDF содержит некорректные границы страницы.');
    }
  }
}

/// Converts a top-left preview selection into the PDF coordinate system.
///
/// The visible page can be rotated. The conversion keeps the crop rectangle
/// aligned with what the user selected in the preview.
class PdfCropGeometry {
  const PdfCropGeometry._();

  static PdfCropBounds toPdfBounds({
    required NormalizedCropRect selection,
    required PdfCropBounds visibleBounds,
    required PdfPageRotation rotation,
  }) {
    selection.validate();
    visibleBounds.validate();

    final width = visibleBounds.width;
    final height = visibleBounds.height;

    late final double left;
    late final double right;
    late final double bottom;
    late final double top;

    switch (rotation) {
      case PdfPageRotation.none:
        left = visibleBounds.left + selection.left * width;
        right = visibleBounds.left + selection.right * width;
        bottom = visibleBounds.bottom + (1 - selection.bottom) * height;
        top = visibleBounds.bottom + (1 - selection.top) * height;
      case PdfPageRotation.clockwise90:
        left = visibleBounds.left + selection.top * width;
        right = visibleBounds.left + selection.bottom * width;
        bottom = visibleBounds.bottom + selection.left * height;
        top = visibleBounds.bottom + selection.right * height;
      case PdfPageRotation.clockwise180:
        left = visibleBounds.left + (1 - selection.right) * width;
        right = visibleBounds.left + (1 - selection.left) * width;
        bottom = visibleBounds.bottom + selection.top * height;
        top = visibleBounds.bottom + selection.bottom * height;
      case PdfPageRotation.clockwise270:
        left = visibleBounds.left + (1 - selection.bottom) * width;
        right = visibleBounds.left + (1 - selection.top) * width;
        bottom = visibleBounds.bottom + (1 - selection.right) * height;
        top = visibleBounds.bottom + (1 - selection.left) * height;
    }

    final result = PdfCropBounds(
      left: left,
      bottom: bottom,
      right: right,
      top: top,
    );
    result.validate();
    if (result.width < 1 || result.height < 1) {
      throw ArgumentError('Область обрезки слишком мала. Минимальный размер: 1 пункт PDF.');
    }
    return result;
  }
}
