import 'dart:developer';

/// Result type returned by Marionette extension callbacks.
sealed class MarionetteExtensionResult {
  const MarionetteExtensionResult();

  /// Creates a successful result with the given [data].
  const factory MarionetteExtensionResult.success(Map<String, dynamic> data) =
      MarionetteExtensionSuccess;

  /// Creates an error result with the given [code] and [detail].
  const factory MarionetteExtensionResult.error(int code, String detail) =
      MarionetteExtensionError;

  /// Creates an invalid parameters error result with the given [detail].
  /// Maps to [ServiceExtensionResponse.invalidParams] (-32602).
  const factory MarionetteExtensionResult.invalidParams(String detail) =
      MarionetteExtensionInvalidParams;
}

/// Successful result with custom data.
/// The helper will add `status`, `type`, and `method` markers automatically.
class MarionetteExtensionSuccess extends MarionetteExtensionResult {
  const MarionetteExtensionSuccess(this.data);

  /// The response data (without status markers -- those are added by the
  /// registration helper).
  final Map<String, dynamic> data;
}

/// Error result mapped to [ServiceExtensionResponse.error] with a custom code.
class MarionetteExtensionError extends MarionetteExtensionResult {
  const MarionetteExtensionError(this.code, this.detail)
      : assert(
          code >= 0 && code <= 16,
          'Error code ($code) must be in the range 0..16 (maps to error codes -32016..-32000).',
        );

  /// Offset from [ServiceExtensionResponse.extensionErrorMin] (-32016).
  /// Valid range: 0..16 (maps to error codes -32016..-32000).
  final int code;

  /// Human-readable error detail.
  final String detail;
}

/// Invalid parameters error mapped to
/// [ServiceExtensionResponse.invalidParams] (-32602).
class MarionetteExtensionInvalidParams extends MarionetteExtensionResult {
  const MarionetteExtensionInvalidParams(this.detail);

  /// Human-readable detail about which parameter is invalid/missing.
  final String detail;
}
