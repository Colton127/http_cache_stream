extension StringExtensions on String {
  String removeWhitespace() {
    return replaceAll(RegExp(r'\s+'), '');
  }
}
