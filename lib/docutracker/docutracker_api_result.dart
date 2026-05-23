/// Typed success/failure for DocuTracker API calls so callers can show server messages.
sealed class DocuTrackerResult<T> {
  const DocuTrackerResult();
}

final class DocuTrackerSuccess<T> extends DocuTrackerResult<T> {
  const DocuTrackerSuccess(this.value);
  final T value;
}

final class DocuTrackerFailure<T> extends DocuTrackerResult<T> {
  const DocuTrackerFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}
