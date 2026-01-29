import 'dart:async';

import 'package:http/http.dart' as http;

import '../../models/exceptions/http_exceptions.dart';

extension HttpClientExtensions on http.Client {
  Future<http.StreamedResponse> sendWithTimeout(
    final http.BaseRequest request,
    final Duration timeout,
  ) {
    final completer = Completer<http.StreamedResponse>();
    final timer = Timer(timeout, () {
      completer.completeError(ResponseTimedOutException(request.url, timeout));
    });

    () async {
      try {
        final response = await send(request);
        if (completer.isCompleted) {
          response.close();
          return;
        }
        completer.complete(response);
      } catch (e) {
        if (completer.isCompleted) return;
        completer.completeError(e);
      } finally {
        timer.cancel();
      }
    }();

    return completer.future;
  }
}

extension HttpStreamedResponseExtensions on http.StreamedResponse {
  ///To cancel the response, we need to call cancel on the stream.
  void close() async {
    try {
      await (stream.listen(null, onError: (_) {}, cancelOnError: true)).cancel();
    } catch (_) {}
  }
}
