import 'dart:async';
import 'dart:convert';

/// Helper function to execute user-provided callbacks safely, ensuring that any exceptions thrown are caught and handled by the current Zone's error handler.
void fireUserCallback(void Function() callback) {
  try {
    callback();
  } catch (e, st) {
    Zone.current.handleUncaughtError(e, st);
  }
}

dynamic jsonDecodeBytes(List<int> bytes) {
  return const Utf8Decoder().fuse(json.decoder).convert(bytes);
}

List<int> jsonEncodeToBytes(Object? object) {
  return json.encoder.fuse(const Utf8Encoder()).convert(object);
}
