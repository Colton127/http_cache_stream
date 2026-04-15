import 'dart:async';
import 'dart:io';

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
        if (_closed) return;

        final prevServer = _server;
        _serverSubscription?.cancel();

        _server = await HttpServer.bind(address, port, shared: true);
        _forwardEvents(_server);

        await prevServer.close(force: true);
      } finally {
        _ensureActiveFuture = null;
      }
    }();
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
