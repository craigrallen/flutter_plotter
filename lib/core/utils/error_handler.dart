import 'package:flutter/foundation.dart';

/// Log an error with context. Replace silent catch blocks with this.
void logError(String context, Object error, [StackTrace? stack]) {
  debugPrint('[Floatilla] $context: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// Format an error for display to user.
String userFacingError(Object error) {
  final msg = error.toString();
  if (msg.contains('SocketException') || msg.contains('Connection refused')) {
    return 'No connection — check your network or server settings';
  }
  if (msg.contains('TimeoutException') || msg.contains('timed out')) {
    return 'Request timed out — server may be unreachable';
  }
  if (msg.contains('401') || msg.contains('Unauthorized')) {
    return 'Not authorised — please log in again';
  }
  if (msg.contains('404')) {
    return 'Resource not found on server';
  }
  if (msg.contains('500')) {
    return 'Server error — please try again later';
  }
  return 'Something went wrong';
}
