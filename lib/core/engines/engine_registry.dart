import 'pdf_engine.dart';

/// Central registry used by the application layer to inspect installed engines.
class EngineRegistry {
  EngineRegistry(Iterable<PdfEngine> engines)
      : _engines = List<PdfEngine>.unmodifiable(engines);

  final List<PdfEngine> _engines;

  List<PdfEngine> get engines => _engines;

  PdfEngine? find(String id) {
    for (final engine in _engines) {
      if (engine.id == id) return engine;
    }
    return null;
  }

  Future<Map<String, EngineStatus>> inspectAll() async {
    final results = <String, EngineStatus>{};
    for (final engine in _engines) {
      results[engine.id] = await engine.checkAvailability();
    }
    return Map.unmodifiable(results);
  }
}
