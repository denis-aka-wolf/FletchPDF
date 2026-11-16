enum OperationStatus {
  succeeded,
  failed,
  cancelled,
}

class OperationResult {
  const OperationResult({
    required this.status,
    required this.message,
    this.outputPaths = const [],
    this.error,
    this.stackTrace,
  });

  final OperationStatus status;
  final String message;
  final List<String> outputPaths;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => status == OperationStatus.succeeded;

  factory OperationResult.success({
    required String message,
    List<String> outputPaths = const [],
  }) {
    return OperationResult(
      status: OperationStatus.succeeded,
      message: message,
      outputPaths: List.unmodifiable(outputPaths),
    );
  }

  factory OperationResult.failure({
    required String message,
    required Object error,
    StackTrace? stackTrace,
  }) {
    return OperationResult(
      status: OperationStatus.failed,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  factory OperationResult.cancelled({String message = 'Операция отменена.'}) {
    return OperationResult(
      status: OperationStatus.cancelled,
      message: message,
    );
  }
}
