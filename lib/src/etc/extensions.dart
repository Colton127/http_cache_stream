extension UriExtensions on Uri {
  //A helper method to get the path and query of a URI
  //This is useful for creating a unique key to identify the request
  String get requestKey {
    return '$path?$query';
  }

  /// Returns a new URI containing only the origin (scheme, host, port).
  Uri get originUri {
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
    );
  }

  ///Creates a new Uri by replacing the origin (scheme, host, port) with the given origin Uri.
  Uri replaceOrigin(
    final Uri origin, {
    String? path,
    Iterable<String>? pathSegments,
    String? query,
    Map<String, dynamic>? queryParameters,
    String? fragment,
  }) {
    return replace(
      scheme: origin.scheme,
      host: origin.host,
      port: origin.port,
      path: path,
      pathSegments: pathSegments,
      query: query,
      queryParameters: queryParameters,
      fragment: fragment,
    );
  }
}

extension FutureExtensions<T> on Future<T> {
  Future<void> ignoreError() async {
    try {
      await this;
    } catch (_) {}
  }

  /// Calls the given [action] when the future completes, regardless of whether it completed with a value or an error.
  /// Used as a replacement for `whenComplete` that does not propagate errors.
  void onComplete(final void Function() action) async {
    try {
      await this;
    } catch (_) {
    } finally {
      action();
    }
  }
}
