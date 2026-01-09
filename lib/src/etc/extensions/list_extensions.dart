extension ListExtensions<T> on List<T> {
  ///Processes each element in the list using [forEach] and removes it from the list.
  ///If [forEach] throws an exception, the element is not removed and the exception is propagated.
  void processAndRemove(final void Function(T element) forEach) {
    for (int i = length - 1; i >= 0; i--) {
      forEach(this[i]);
      removeAt(i);
    }
  }
}
