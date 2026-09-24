import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// A wrapper around [HttpServer] that keeps the server alive by periodically checking its health and restarting it if necessary.
/// Workaround for https://github.com/dart-lang/sdk/issues/63168
class KeepAliveServer {
  HttpServer _server;
  final InternetAddress address;
  final int port;

  late final StreamController<HttpRequest> _controller;
  StreamSubscription<HttpRequest>? _serverSubscription;
  Future<void>? _ensureActiveFuture;
  Timer? _healthCheckTimer;
  bool _closed = false;

  static const defaultHealthCheckInterval = Duration(seconds: 5);

  KeepAliveServer._(this._server, {Duration? healthCheckInterval})
      : address = _server.address,
        port = _server.port {
    _controller = StreamController<HttpRequest>(
      sync: true,
      onCancel: close,
      onPause: () => _serverSubscription?.pause(),
      onResume: () => _serverSubscription?.resume(),
    );
    _forwardEvents(_server);

    if (healthCheckInterval != null && healthCheckInterval > Duration.zero) {
      _healthCheckTimer =
          Timer.periodic(healthCheckInterval, (_) => ensureActive().ignore());
    }
  }

  static Future<KeepAliveServer> bind(Object address, int port,
      {Duration? healthCheckInterval}) async {
    healthCheckInterval ??= Platform.isIOS ? defaultHealthCheckInterval : null;
    final server = await HttpServer.bind(address, port, shared: true);
    return KeepAliveServer._(server, healthCheckInterval: healthCheckInterval);
  }

  void _forwardEvents(HttpServer server) {
    _serverSubscription?.cancel();
    _serverSubscription = server.listen(_controller.add,
        onError: _controller.addError, cancelOnError: false);
  }

  Future<bool> isAlive() async {
    if (_closed) return false;
    try {
      final socket = await Socket.connect(address, port,
          timeout: const Duration(milliseconds: 500));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureActive() {
    if (_closed) return Future.value();

    return _ensureActiveFuture ??= () async {
      try {
        if (await isAlive()) return;
        await rebind();
      } finally {
        _ensureActiveFuture = null;
      }
    }();
  }

  /// Replaces the listening socket with a new one on the same address and port.
  ///
  /// The current server must be closed before binding: within one process, a
  /// `shared` bind to an (address, port) that is still open reuses the existing
  /// listening socket rather than creating a new one, so binding first would
  /// re-attach to the same dead socket. Closing without `force` leaves requests
  /// already in progress untouched.
  @visibleForTesting
  Future<void> rebind() async {
    if (_closed) return;
    final prevSubscription = _serverSubscription;
    _serverSubscription = null;
    await prevSubscription?.cancel();
    await _server.close();
    if (_closed) return;

    final server = await HttpServer.bind(address, port, shared: true);
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    _forwardEvents(server);
  }

  StreamSubscription<HttpRequest> listen(
      void Function(HttpRequest event)? onData,
      {Function? onError,
      void Function()? onDone,
      bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;
    _healthCheckTimer?.cancel();
    await _serverSubscription?.cancel();
    await _controller.close();
    return _server.close(force: force);
  }
}
