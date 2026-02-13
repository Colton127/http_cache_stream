import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../etc/timeout_timer.dart';

class SocketHandler {
  final Socket _socket;
  SocketHandler(this._socket);

  Future<void> writeResponse(
    final Stream<List<int>> response,
    final Duration timeout,
  ) async {
    final timeoutTimer = TimeoutTimer(timeout)..start(destroy);
    StreamSubscription<Uint8List>? socketSubscription;

    try {
      socketSubscription = _socket.listen(
        null, //Drain the socket
        onDone: destroy, //Client sent FIN
        onError: (_) => destroy(), //Error on socket
        cancelOnError: true,
      );

      await _socket.addStream(response.map((data) {
        timeoutTimer.reset();
        return data;
      }));

      if (_closed) return;
      timeoutTimer.reset();
      await _socket.flush();
      if (_closed) return;
      await _socket.close();
    } catch (e) {
      //Intentionally ignored.
    } finally {
      socketSubscription?.cancel().ignore();
      timeoutTimer.cancel();
      destroy(); //Not calling [destroy], even following socket.close, results in resource leaks
    }
  }

  void destroy() {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }

  bool _closed = false;
  bool get isClosed => _closed;
}
