extension UriExtensions on Uri {
  RequestKey get requestKey {
    return RequestKey(this);
  }

  Uri replaceOrigin(Uri newOrigin) {
    return replace(
      scheme: newOrigin.scheme,
      host: newOrigin.host,
      port: newOrigin.port,
    );
  }

  Uri get originUri {
    return Uri(scheme: scheme, host: host, port: port);
  }

  bool originEquals(Uri other) {
    return host == other.host && port == other.port && scheme == other.scheme;
  }
}

extension type const RequestKey._(String _value) implements String {
  factory RequestKey(Uri uri) =>
      RequestKey._('${uri.host}${uri.path}?${uri.query}');
}
