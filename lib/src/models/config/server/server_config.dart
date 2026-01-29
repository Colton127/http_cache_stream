import 'dart:io';

import 'package:flutter/foundation.dart';

/// Configuration for the local cache server.
class CacheServerConfig {
  /// The host to bind the server to. Defaults to [InternetAddress.loopbackIPv4].
  ///
  /// Accepts IP strings (e.g., '127.0.0.1', '0.0.0.0').
  /// If null, defaults to [InternetAddress.loopbackIPv4].
  final String? host;

  /// The port to bind the server to. Defaults to a random available port.
  final int? port;
  const CacheServerConfig({this.host, this.port});

  /// Creates the HttpServer.
  ///
  /// Override this to use [HttpServer.bindSecure] or custom socket options.
  ///
  /// Not intended for public use.
  @visibleForOverriding
  Future<HttpServer> createServer() {
    return HttpServer.bind(
      host ?? InternetAddress.loopbackIPv4,
      port ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheServerConfig && other.host == host && other.port == port;
  }

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}
