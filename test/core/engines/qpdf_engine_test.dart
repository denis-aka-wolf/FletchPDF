import 'package:fletchpdf/core/engines/qpdf_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QpdfEngine', () {
    test('rejects merge with fewer than two input files', () async {
      final engine = QpdfEngine(executablePath: 'qpdf-not-installed');

      await expectLater(
        engine.merge(
          inputPaths: const ['one.pdf'],
          outputPath: 'merged.pdf',
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty input paths', () async {
      final engine = QpdfEngine(executablePath: 'qpdf-not-installed');

      await expectLater(
        engine.merge(
          inputPaths: const ['', 'two.pdf'],
          outputPath: 'merged.pdf',
        ),
        throwsArgumentError,
      );
    });
  });
}
