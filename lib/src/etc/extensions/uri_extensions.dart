extension UriExtensions on Uri {
  //A helper method to get the path and query of a URI
  //This is useful for creating a unique key to identify the request
  String get requestKey {
    return '$path?$query';
  }

  ///Replaces the scheme, host, and port of this [Uri] with those from [origin].
  Uri replaceOrigin(final Uri origin) {
    return replace(
      scheme: origin.scheme,
      host: origin.host,
      port: origin.port,
    );
  }

  Uri get originUri {
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
    );
  }

  static bool isSameOrigin(final Uri uri1, final Uri uri2) {
    return uri1.host == uri2.host && uri1.port == uri2.port && uri1.scheme == uri2.scheme;
  }
}
