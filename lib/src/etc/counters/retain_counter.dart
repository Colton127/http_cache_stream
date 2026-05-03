class RetainCounter {
  RetainCounter();
  int _retainCount = 1;

  void retain() {
    _retainCount++;
  }

  void release({bool force = false}) {
    if (!isRetained) return;
    _retainCount = force ? 0 : _retainCount - 1;
  }

  bool get isRetained => _retainCount != 0;
  int get count => _retainCount;
}
