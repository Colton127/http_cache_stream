
extension ListExtensions<T> on List<T> {
  ///Processes each element in the list using [forEach] and removes it from the list.
  void processAndRemove(final void Function(T element) forEach) {
    for (int i = length - 1; i >= 0; i--) {
      forEach(this[i]);
      removeAt(i);
    }
  }
}

extension SortedListExtensions<T extends Comparable<T>> on List<T> {
  void addSorted(T value) {
    for (int i = 0; i < length; i++) {
      if (value.compareTo(this[i]) < 0) {
        insert(i, value);
        return;
      }
    }

    add(value);
  }
}
