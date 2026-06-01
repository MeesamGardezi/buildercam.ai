sealed class AsyncState<T> {
  const AsyncState();

  bool get isLoading => this is AsyncLoading<T>;
  bool get hasData => this is AsyncData<T>;
  bool get hasError => this is AsyncError<T>;

  T? get dataOrNull => switch (this) {
        AsyncData<T>(:final value) => value,
        _ => null,
      };

  R when<R>({
    required R Function() loading,
    required R Function(T value) data,
    required R Function(Object error, StackTrace stackTrace) error,
  }) =>
      switch (this) {
        AsyncLoading<T>() => loading(),
        AsyncData<T>(:final value) => data(value),
        AsyncError<T>(error: final err, stackTrace: final st) => error(err, st),
      };
}

final class AsyncLoading<T> extends AsyncState<T> {
  const AsyncLoading();
}

final class AsyncData<T> extends AsyncState<T> {
  final T value;
  const AsyncData(this.value);
}

final class AsyncError<T> extends AsyncState<T> {
  final Object error;
  final StackTrace stackTrace;
  const AsyncError(this.error, this.stackTrace);

  String get message => error.toString();
}
