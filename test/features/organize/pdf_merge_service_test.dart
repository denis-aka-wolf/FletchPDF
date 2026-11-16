import 'dart:io';

import 'package:fletchpdf/features/organize/services/pdf_merge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late PdfMergeService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fletchpdf_merge_test_',
    );
    service = const PdfMergeService();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('requires at least two input documents', () async {
    expect(
      () => service.merge(
        inputPaths: const ['one.pdf'],
        outputPath: '${temporaryDirectory.path}/merged.pdf',
      ),
      throwsArgumentError,
    );
  });

  test('rejects the same input path more than once', () async {
    final input = File('${temporaryDirectory.path}/source.pdf');
    await input.writeAsBytes([1, 2, 3]);

    expect(
      () => service.merge(
        inputPaths: [input.path, input.path],
        outputPath: '${temporaryDirectory.path}/merged.pdf',
      ),
      throwsArgumentError,
    );
  });

  test('does not allow the output to replace an input document', () async {
    final input = File('${temporaryDirectory.path}/source.pdf');
    final secondInput = File('${temporaryDirectory.path}/second.pdf');
    await input.writeAsBytes([1, 2, 3]);
    await secondInput.writeAsBytes([4, 5, 6]);

    expect(
      () => service.merge(
        inputPaths: [input.path, secondInput.path],
        outputPath: input.path,
      ),
      throwsArgumentError,
    );
  });

  test('rejects an existing output unless overwrite is confirmed', () async {
    final firstInput = File('${temporaryDirectory.path}/first.pdf');
    final secondInput = File('${temporaryDirectory.path}/second.pdf');
    final output = File('${temporaryDirectory.path}/merged.pdf');
    await firstInput.writeAsBytes([1, 2, 3]);
    await secondInput.writeAsBytes([4, 5, 6]);
    await output.writeAsBytes([7, 8, 9]);

    expect(
      () => service.merge(
        inputPaths: [firstInput.path, secondInput.path],
        outputPath: output.path,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await output.readAsBytes(), [7, 8, 9]);
  });
}
