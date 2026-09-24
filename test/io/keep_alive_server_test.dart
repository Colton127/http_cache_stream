import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/src/cache_server/keep_alive_server.dart';

/// Identifies the kernel socket listening on [port] in this process, or null
/// when lsof is unavailable or reports no identity for the socket.
Future<String?> _listeningSocketId(int port) async {
  try {
    final result = await Process.run('lsof', [
      '-a',
      '-p',
      '$pid',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-Fdi',
    ]);
    if (result.exitCode != 0) return null;
    final ids = (result.stdout as String)
        .split('\n')
        .where((line) => line.startsWith('d') || line.startsWith('i'))
        .join(',');
    return ids.isEmpty ? null : ids;
  } on ProcessException {
    return null;
  }
}

Future<String> _get(KeepAliveServer server) async {
  final client = HttpClient();
  try {
    final request = await client.get(server.address.host, server.port, '/');
    final response = await request.close();
    return await response.transform(const SystemEncoding().decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  late KeepAliveServer server;

  setUp(() async {
    server = await KeepAliveServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..write('ok')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  test('rebind keeps serving requests on the same port', () async {
    expect(await _get(server), 'ok');
    await server.rebind();
    expect(await server.isAlive(), isTrue);
    expect(await _get(server), 'ok');
  });

  test('rebind replaces the listening socket instead of reusing it', () async {
    final before = await _listeningSocketId(server.port);
    if (before == null) {
      markTestSkipped('lsof is unavailable');
      return;
    }
    await server.rebind();
    final after = await _listeningSocketId(server.port);
    expect(after, isNotNull);
    expect(after, isNot(before),
        reason: 'a dead listening socket must not survive a rebind');
  });

  test('ensureActive leaves a healthy server untouched', () async {
    final before = await _listeningSocketId(server.port);
    await server.ensureActive();
    expect(await _listeningSocketId(server.port), before);
    expect(await _get(server), 'ok');
  });
}
