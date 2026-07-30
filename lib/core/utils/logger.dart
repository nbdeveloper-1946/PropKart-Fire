import 'package:flutter/foundation.dart';

class BeautifulLogger {
  static void logTelemetry(String operation, {
    int isarReadMs = 0,
    int networkMs = 0,
    int jsonParseMs = 0,
    int isarWriteMs = 0,
    required int totalMs,
  }) {
    if (!kDebugMode) return;

    // Suppress telemetry logs if they are fast/regular, but print summaries of sync/heavy tasks.
    if (operation.contains('Realtime Event') && totalMs < 50) return;
    if (operation.contains('SyncManager') && totalMs < 20) return;

    final buffer = StringBuffer();
    buffer.write('⚡ [TELEMETRY] ${operation.padRight(40)} | ');
    buffer.write('Total: ${totalMs.toString().padLeft(4)}ms');
    if (isarReadMs > 0) buffer.write(' • Read: ${isarReadMs}ms');
    if (isarWriteMs > 0) buffer.write(' • Write: ${isarWriteMs}ms');
    if (networkMs > 0) buffer.write(' • Net: ${networkMs}ms');
    if (jsonParseMs > 0) buffer.write(' • Parse: ${jsonParseMs}ms');

    print(buffer.toString());
  }

  static void info(String message) {
    if (!kDebugMode) return;
    print('ℹ️ [INFO] $message');
  }

  static void success(String message) {
    if (!kDebugMode) return;
    print('✅ [SUCCESS] $message');
  }

  static void warning(String message) {
    if (!kDebugMode) return;
    print('⚠️ [WARNING] $message');
  }

  static void error(String message, [dynamic error]) {
    if (!kDebugMode) return;
    if (error != null) {
      print('❌ [ERROR] $message | Details: $error');
    } else {
      print('❌ [ERROR] $message');
    }
  }

  static void sync(String message) {
    if (!kDebugMode) return;
    print('🔄 [SYNC] $message');
  }
}
