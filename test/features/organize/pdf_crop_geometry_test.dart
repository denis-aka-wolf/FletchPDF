import 'package:fletchpdf/features/organize/services/pdf_crop_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  const visible = PdfCropBounds(
    left: 10,
    bottom: 20,
    right: 210,
    top: 320,
  );
  const selection = NormalizedCropRect(
    left: 0.1,
    top: 0.2,
    right: 0.8,
    bottom: 0.9,
  );

  group('PdfCropGeometry', () {
    test('maps an unrotated page selection', () {
      final result = PdfCropGeometry.toPdfBounds(
        selection: selection,
        visibleBounds: visible,
        rotation: PdfPageRotation.none,
      );

      expect(result.left, closeTo(30, 0.001));
      expect(result.right, closeTo(170, 0.001));
      expect(result.bottom, closeTo(50, 0.001));
      expect(result.top, closeTo(260, 0.001));
    });

    test('maps a clockwise 90 degree page selection', () {
      final result = PdfCropGeometry.toPdfBounds(
        selection: selection,
        visibleBounds: visible,
        rotation: PdfPageRotation.clockwise90,
      );

      expect(result.left, closeTo(50, 0.001));
      expect(result.right, closeTo(190, 0.001));
      expect(result.bottom, closeTo(50, 0.001));
      expect(result.top, closeTo(260, 0.001));
    });

    test('maps a 180 degree page selection', () {
      final result = PdfCropGeometry.toPdfBounds(
        selection: selection,
        visibleBounds: visible,
        rotation: PdfPageRotation.clockwise180,
      );

      expect(result.left, closeTo(50, 0.001));
      expect(result.right, closeTo(190, 0.001));
      expect(result.bottom, closeTo(80, 0.001));
      expect(result.top, closeTo(290, 0.001));
    });

    test('maps a clockwise 270 degree page selection', () {
      final result = PdfCropGeometry.toPdfBounds(
        selection: selection,
        visibleBounds: visible,
        rotation: PdfPageRotation.clockwise270,
      );

      expect(result.left, closeTo(30, 0.001));
      expect(result.right, closeTo(170, 0.001));
      expect(result.bottom, closeTo(80, 0.001));
      expect(result.top, closeTo(290, 0.001));
    });

    test('rejects an empty or out-of-page selection', () {
      expect(
        () => PdfCropGeometry.toPdfBounds(
          selection: const NormalizedCropRect(
            left: 0.4,
            top: 0.2,
            right: 0.4,
            bottom: 0.9,
          ),
          visibleBounds: visible,
          rotation: PdfPageRotation.none,
        ),
        throwsArgumentError,
      );
      expect(
        () => PdfCropGeometry.toPdfBounds(
          selection: const NormalizedCropRect(
            left: -0.1,
            top: 0.2,
            right: 0.8,
            bottom: 0.9,
          ),
          visibleBounds: visible,
          rotation: PdfPageRotation.none,
        ),
        throwsArgumentError,
      );
    });
  });
}
