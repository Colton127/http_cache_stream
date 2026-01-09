extension UriExtensions on Uri {
  //A helper method to get the path and query of a URI
  //This is useful for creating a unique key to identify the request
  String get requestKey {
    return '$path?$query';
  }
}
