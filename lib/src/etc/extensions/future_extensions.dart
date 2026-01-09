extension FutureExtensions<T> on Future<T> {
  ///Registers a callback to be called when the future completes, regardless of whether it completed with a value or an error.
  ///Differs from [whenComplete] by ignoring any errors thrown by the future.
  void onComplete(final Function() callback) async {
    try {
      await this;
    } catch (_) {
      //Ignore errors
    } finally {
      callback();
    }
  }
}
