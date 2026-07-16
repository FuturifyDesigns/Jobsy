import 'package:flutter/foundation.dart';

/// Logs only in debug builds — avoids leaking tokens/PII in release logs.
void secureLog(String message, {Object? error}) {
  if (!kDebugMode) return;
  if (error != null) {
    debugPrint('[Jobsy] $message — $error');
  } else {
    debugPrint('[Jobsy] $message');
  }
}
