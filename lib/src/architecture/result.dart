/// Zero-allocation, exception-free Result type for Clean Architecture.
sealed class Result<S, F> {
  const Result();

  bool get isSuccess => this is Success<S, F>;
  bool get isFailure => this is Failure<S, F>;

  S? get dataOrNull => switch (this) {
        Success(data: final d) => d,
        Failure() => null,
      };

  F? get errorOrNull => switch (this) {
        Success() => null,
        Failure(error: final e) => e,
      };

  R fold<R>({
    required R Function(S data) onSuccess,
    required R Function(F error) onFailure,
  }) {
    return switch (this) {
      Success(data: final d) => onSuccess(d),
      Failure(error: final e) => onFailure(e),
    };
  }
}

class Success<S, F> extends Result<S, F> {
  final S data;
  const Success(this.data);
}

class Failure<S, F> extends Result<S, F> {
  final F error;
  const Failure(this.error);
}
