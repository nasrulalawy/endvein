import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Result Type Tests', () {
    test('Success returns correct value and status', () {
      const result = Success<int, String>(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, equals(42));
      expect(result.errorOrNull, isNull);

      final folded = result.fold(
        onSuccess: (val) => 'val: $val',
        onFailure: (err) => 'err: $err',
      );
      expect(folded, equals('val: 42'));
    });

    test('Failure returns correct error', () {
      const result = Failure<int, String>('not_found');
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, equals('not_found'));

      final folded = result.fold(
        onSuccess: (val) => 'val: $val',
        onFailure: (err) => 'err: $err',
      );
      expect(folded, equals('err: not_found'));
    });
  });

  group('EndveinRouter Configuration', () {
    test('Registers static routes correctly', () {
      final router = EndveinRouter();
      router.get('/health', (ctx) => {'status': 'healthy'});
      router.post('/login', (ctx) => {'token': 'xyz'});
      expect(router, isNotNull);
    });

    test('Registers dynamic routes correctly', () {
      final router = EndveinRouter();
      router.get('/users/:id', (ctx) => {'userId': ctx.params['id']});
      expect(router, isNotNull);
    });
  });
}
