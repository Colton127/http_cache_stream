extension UriExtensions on Uri {
  //A helper method to get the path and query of a URI
  //This is useful for creating a unique key to identify the request
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
  factory RequestKey(Uri uri) => RequestKey._('${uri.path}?${uri.query}');
}
