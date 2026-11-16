import 'package:fletchpdf/core/engines/engine_registry.dart';
import 'package:fletchpdf/core/engines/pdf_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements PdfEngine {
  _FakeEngine(this.id, this.status);

  @override
  final String id;

  final EngineStatus status;

  @override
  String get displayName => id.toUpperCase();

  @override
  Future<EngineStatus> checkAvailability() async => status;
}

void main() {
  group('EngineRegistry', () {
    test('finds engines by stable identifier', () {
      final engine = _FakeEngine(
        'test-engine',
        const EngineStatus(available: true),
      );
      final registry = EngineRegistry([engine]);

      expect(registry.find('test-engine'), same(engine));
      expect(registry.find('missing'), isNull);
    });

    test('inspects every registered engine', () async {
      final registry = EngineRegistry([
        _FakeEngine(
          'available',
          const EngineStatus(available: true, version: '1.0'),
        ),
        _FakeEngine(
          'missing',
          const EngineStatus(
            available: false,
            message: 'Не установлен',
          ),
        ),
      ]);

      final statuses = await registry.inspectAll();

      expect(statuses['available']?.available, isTrue);
      expect(statuses['available']?.version, '1.0');
      expect(statuses['missing']?.available, isFalse);
      expect(statuses['missing']?.message, 'Не установлен');
    });
  });
}
