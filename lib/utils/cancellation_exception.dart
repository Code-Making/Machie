/// An exception thrown when an operation is cancelled by a CancelToken.
class CancellationException implements Exception {
  final String message;

  CancellationException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'CancellationException: $message';
}