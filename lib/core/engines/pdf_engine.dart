abstract interface class PdfEngine {
  String get id;

  String get displayName;

  Future<EngineStatus> checkAvailability();
}

class EngineStatus {
  const EngineStatus({
    required this.available,
    this.version,
    this.message,
  });

  final bool available;
  final String? version;
  final String? message;
}
