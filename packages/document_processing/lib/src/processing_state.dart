import 'dart:math' as math;

const documentProcessingMetadataKey = 'documentProcessing';

enum DocumentProcessingPhase {
  queued,
  extracting,
  retryScheduled,
  succeeded,
  failed,
  cancelled,
}

final class DocumentRetryPolicy {
  const DocumentRetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 2),
    this.processingTimeout = const Duration(minutes: 3),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration processingTimeout;
}

final class DocumentProcessingState {
  const DocumentProcessingState._({
    required this.phase,
    required this.attempt,
    required this.maxAttempts,
    required this.updatedAt,
    this.startedAt,
    this.nextAttemptAt,
    this.completedAt,
    this.providerId,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final DocumentProcessingPhase phase;
  final int attempt;
  final int maxAttempts;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? nextAttemptAt;
  final DateTime? completedAt;
  final String? providerId;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  bool get isTerminal => switch (phase) {
        DocumentProcessingPhase.succeeded ||
        DocumentProcessingPhase.failed ||
        DocumentProcessingPhase.cancelled => true,
        _ => false,
      };

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'phase': phase.name,
        'attempt': attempt,
        'maxAttempts': maxAttempts,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (startedAt != null)
          'startedAt': startedAt!.toUtc().toIso8601String(),
        if (nextAttemptAt != null)
          'nextAttemptAt': nextAttemptAt!.toUtc().toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        if (providerId != null) 'providerId': providerId,
        if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
        if (lastErrorMessage != null) 'lastErrorMessage': lastErrorMessage,
      };

  factory DocumentProcessingState.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version != 1) {
      throw FormatException('Unsupported document processing schema: $version');
    }

    final state = DocumentProcessingState._(
      phase: DocumentProcessingPhase.values.byName(json['phase']! as String),
      attempt: json['attempt']! as int,
      maxAttempts: json['maxAttempts']! as int,
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      startedAt: _parseOptionalDate(json['startedAt']),
      nextAttemptAt: _parseOptionalDate(json['nextAttemptAt']),
      completedAt: _parseOptionalDate(json['completedAt']),
      providerId: json['providerId'] as String?,
      lastErrorCode: json['lastErrorCode'] as String?,
      lastErrorMessage: json['lastErrorMessage'] as String?,
    );
    _validateState(state);
    return state;
  }

  static DateTime? _parseOptionalDate(Object? value) => switch (value) {
        final String text when text.isNotEmpty => DateTime.parse(text).toUtc(),
        _ => null,
      };

  static void _validateState(DocumentProcessingState state) {
    if (state.maxAttempts < 1) {
      throw const FormatException('maxAttempts must be at least 1');
    }
    if (state.attempt < 0 || state.attempt > state.maxAttempts) {
      throw const FormatException('attempt is outside the allowed range');
    }
    if (state.phase == DocumentProcessingPhase.extracting &&
        state.startedAt == null) {
      throw const FormatException('extracting state requires startedAt');
    }
    if (state.phase == DocumentProcessingPhase.retryScheduled &&
        state.nextAttemptAt == null) {
      throw const FormatException('retryScheduled state requires nextAttemptAt');
    }
    if (state.isTerminal && state.completedAt == null) {
      throw const FormatException('terminal processing state requires completedAt');
    }
  }
}

final class DocumentRetryStateMachine {
  DocumentRetryStateMachine({
    this.policy = const DocumentRetryPolicy(),
  }) {
    _validatePolicy(policy);
  }

  final DocumentRetryPolicy policy;

  DocumentProcessingState initial({required DateTime at}) =>
      DocumentProcessingState._(
        phase: DocumentProcessingPhase.queued,
        attempt: 0,
        maxAttempts: policy.maxAttempts,
        updatedAt: at.toUtc(),
      );

  bool canStart(DocumentProcessingState state, {required DateTime at}) {
    final now = at.toUtc();
    return switch (state.phase) {
      DocumentProcessingPhase.queued => true,
      DocumentProcessingPhase.retryScheduled =>
        !now.isBefore(state.nextAttemptAt!),
      _ => false,
    };
  }

  DocumentProcessingState begin(
    DocumentProcessingState state, {
    required DateTime at,
    required String providerId,
  }) {
    final now = at.toUtc();
    final normalizedProvider = providerId.trim();
    if (normalizedProvider.isEmpty) {
      throw const FormatException('providerId cannot be empty');
    }
    if (!canStart(state, at: now)) {
      throw StateError('Document processing is not eligible to start');
    }
    if (state.attempt >= state.maxAttempts) {
      throw StateError('Document processing has exhausted its attempts');
    }

    return DocumentProcessingState._(
      phase: DocumentProcessingPhase.extracting,
      attempt: state.attempt + 1,
      maxAttempts: state.maxAttempts,
      updatedAt: now,
      startedAt: now,
      providerId: normalizedProvider,
      lastErrorCode: state.lastErrorCode,
      lastErrorMessage: state.lastErrorMessage,
    );
  }

  DocumentProcessingState succeed(
    DocumentProcessingState state, {
    required DateTime at,
  }) {
    _requireExtracting(state);
    final now = at.toUtc();
    return DocumentProcessingState._(
      phase: DocumentProcessingPhase.succeeded,
      attempt: state.attempt,
      maxAttempts: state.maxAttempts,
      updatedAt: now,
      startedAt: state.startedAt,
      completedAt: now,
      providerId: state.providerId,
    );
  }

  DocumentProcessingState fail(
    DocumentProcessingState state, {
    required DateTime at,
    required bool retryable,
    required String code,
    required String message,
  }) {
    _requireExtracting(state);
    final now = at.toUtc();
    final errorCode = code.trim();
    final errorMessage = message.trim();
    if (errorCode.isEmpty) {
      throw const FormatException('failure code cannot be empty');
    }
    if (errorMessage.isEmpty) {
      throw const FormatException('failure message cannot be empty');
    }

    final canRetry = retryable && state.attempt < state.maxAttempts;
    if (canRetry) {
      return DocumentProcessingState._(
        phase: DocumentProcessingPhase.retryScheduled,
        attempt: state.attempt,
        maxAttempts: state.maxAttempts,
        updatedAt: now,
        startedAt: state.startedAt,
        nextAttemptAt: now.add(delayAfterAttempt(state.attempt)),
        providerId: state.providerId,
        lastErrorCode: errorCode,
        lastErrorMessage: errorMessage,
      );
    }

    return DocumentProcessingState._(
      phase: DocumentProcessingPhase.failed,
      attempt: state.attempt,
      maxAttempts: state.maxAttempts,
      updatedAt: now,
      startedAt: state.startedAt,
      completedAt: now,
      providerId: state.providerId,
      lastErrorCode: errorCode,
      lastErrorMessage: errorMessage,
    );
  }

  DocumentProcessingState cancel(
    DocumentProcessingState state, {
    required DateTime at,
  }) {
    if (state.isTerminal) return state;
    final now = at.toUtc();
    return DocumentProcessingState._(
      phase: DocumentProcessingPhase.cancelled,
      attempt: state.attempt,
      maxAttempts: state.maxAttempts,
      updatedAt: now,
      startedAt: state.startedAt,
      completedAt: now,
      providerId: state.providerId,
      lastErrorCode: state.lastErrorCode,
      lastErrorMessage: state.lastErrorMessage,
    );
  }

  DocumentProcessingState recoverInterrupted(
    DocumentProcessingState state, {
    required DateTime at,
  }) {
    if (state.phase != DocumentProcessingPhase.extracting) return state;
    final now = at.toUtc();
    final deadline = state.startedAt!.add(policy.processingTimeout);
    if (now.isBefore(deadline)) return state;
    return fail(
      state,
      at: now,
      retryable: true,
      code: 'processing_interrupted',
      message: '上一轮文档解析未完成，已进入受控重试流程',
    );
  }

  Duration delayAfterAttempt(int attempt) {
    if (attempt < 1) {
      throw RangeError.range(attempt, 1, null, 'attempt');
    }
    var microseconds = policy.baseDelay.inMicroseconds;
    final maximum = policy.maxDelay.inMicroseconds;
    for (var index = 1; index < attempt; index++) {
      if (microseconds >= maximum) break;
      microseconds = math.min(microseconds * 2, maximum).toInt();
    }
    return Duration(
      microseconds: math.min(microseconds, maximum).toInt(),
    );
  }

  static void _requireExtracting(DocumentProcessingState state) {
    if (state.phase != DocumentProcessingPhase.extracting) {
      throw StateError('Document processing transition requires extracting state');
    }
  }

  static void _validatePolicy(DocumentRetryPolicy policy) {
    if (policy.maxAttempts < 1) {
      throw ArgumentError.value(policy.maxAttempts, 'maxAttempts');
    }
    if (policy.baseDelay <= Duration.zero) {
      throw ArgumentError.value(policy.baseDelay, 'baseDelay');
    }
    if (policy.maxDelay < policy.baseDelay) {
      throw ArgumentError.value(policy.maxDelay, 'maxDelay');
    }
    if (policy.processingTimeout <= Duration.zero) {
      throw ArgumentError.value(
        policy.processingTimeout,
        'processingTimeout',
      );
    }
  }
}

DocumentProcessingState? documentProcessingStateFromMetadata(
  Map<String, Object?> metadata,
) {
  final raw = metadata[documentProcessingMetadataKey];
  if (raw == null) return null;
  if (raw is! Map) {
    throw const FormatException('document processing metadata must be a map');
  }
  return DocumentProcessingState.fromJson(Map<String, Object?>.from(raw));
}

Map<String, Object?> withDocumentProcessingState(
  Map<String, Object?> metadata,
  DocumentProcessingState state,
) =>
    {
      ...metadata,
      documentProcessingMetadataKey: state.toJson(),
    };
