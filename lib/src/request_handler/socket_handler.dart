import 'dart:async';
import 'dart:developer';
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
    StreamSubscription<Uint8List>? listener;

    try {
      listener = _socket.listen(
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
      log('SocketHandler: Successfully wrote response and closed socket');
    } catch (e) {
      log('SocketHandler: Error while writing response: $e');
      //Intentionally ignored.
    } finally {
      listener?.cancel().ignore();
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


// class SocketHandler {
//   final Socket _socket;
//   SocketHandler(this._socket);
//   final int id = DateTime.now().microsecondsSinceEpoch;

//   Future<void> writeResponse(
//     final Stream<List<int>> response,
//     final Duration timeout,
//   ) async {
//     log('Socket $id: Starting to write response');
//     final timeoutTimer = TimeoutTimer(timeout)..start(destroy);
//     final bool listenerDone = false;
//     int eventsAfterDone = 0;

//     try {
//       _socket.drain()
//       final listener = _socket.listen(
//         (_) {},
//         onError: (e) {
//           log('Socket $id: Listener error: $e');
//         },
//         onDone: () {
//           log('Socket $id: Listener done');
//           listenerDone = true;
//         },
//         cancelOnError: false,
//       );

//       try {
//         await _socket.addStream(response.map((data) {
//           timeoutTimer.reset();
//           if (listenerDone) {
//             eventsAfterDone += 1;
//           }
//           return data;
//         }));
//       } catch (e) {
//         if (e is SocketException) {
//           rethrow;
//         }
//         log('Socket $id: Error while adding stream: $e');
//         //Swallow exceptions from addStream, so that we can still try to flush and close the socket.
//       }
//       if (_closed) return;
//       timeoutTimer.reset();
//       await _socket.flush();
//       if (_closed) return;
//       await _socket.close();
//     } catch (e) {
//       log('Socket $id: Error while writing response: $e');
//       //Intentionally ignored.
//     } finally {
//       timeoutTimer.cancel();

//       destroy(); //Not calling [destroy], even following socket.close, results in resource leaks
//       log('Socket $id: Finished writing response. Sent $eventsAfterDone events after listener was done.');
//     }
//   }

//   void destroy() {
//     if (_closed) return;
//     _closed = true;
//     _socket.destroy();
//   }

//   bool _closed = false;
//   bool get isClosed => _closed;
// }