import 'dart:async';
import 'result.dart';

/// Contract for Clean Architecture Use Cases.
/// Pure business logic, independent of HTTP, DB, or Frameworks.
abstract interface class UseCase<T, Params> {
  FutureOr<Result<T, Exception>> call(Params params);
}

/// Helper for Use Cases that require no parameters.
class NoParams {
  const NoParams();
}
