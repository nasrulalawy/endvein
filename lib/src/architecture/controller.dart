import '../core/http/context.dart';
import '../core/http/router.dart';

/// Base Controller for Clean Architecture presentation layer.
abstract class BaseController {
  void mount(EndveinRouter router);
}

/// Utility extensions on [EndveinContext] for clean controller responses.
extension ControllerContextX on EndveinContext {
  void success(Object? data, {int statusCode = 200}) {
    json({
      'success': true,
      'data': data,
    }, statusCode: statusCode);
  }

  void fail(String message, {int statusCode = 400, Object? details}) {
    json({
      'success': false,
      'error': message,
      if (details != null) 'details': details,
    }, statusCode: statusCode);
  }
}
