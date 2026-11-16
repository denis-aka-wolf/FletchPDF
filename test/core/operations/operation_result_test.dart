import 'package:flutter_test/flutter_test.dart';
import 'package:fletchpdf/core/operations/operation_result.dart';

void main() {
  group('OperationResult', () {
    test('success stores immutable output paths', () {
      final result = OperationResult.success(
        message: 'Готово',
        outputPaths: const ['merged.pdf'],
      );

      expect(result.succeeded, isTrue);
      expect(result.status, OperationStatus.succeeded);
      expect(result.outputPaths, ['merged.pdf']);
    });

    test('failure preserves error information', () {
      final error = StateError('QPDF недоступен');
      final result = OperationResult.failure(
        message: 'Ошибка',
        error: error,
      );

      expect(result.succeeded, isFalse);
      expect(result.status, OperationStatus.failed);
      expect(result.error, same(error));
    });

    test('cancelled result has cancelled status', () {
      final result = OperationResult.cancelled();

      expect(result.status, OperationStatus.cancelled);
      expect(result.message, 'Операция отменена.');
    });
  });
}
