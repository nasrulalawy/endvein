import 'dart:io';
import 'package:endvein/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein CLI Scaffolding Tests', () {
    test('Runner returns 0 for --help', () async {
      final runner = EndveinCommandRunner();
      final code = await runner.run(['--help']);
      expect(code, equals(0));
    });

    test('Runner returns 64 for missing command arguments', () async {
      final runner = EndveinCommandRunner();
      final code = await runner.run(['create']);
      expect(code, equals(64));
    });

    test('Create command scaffolds complete project', () async {
      final tempDir = Directory('test_temp_project');
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }

      final runner = EndveinCommandRunner();
      final code = await runner.run(['create', 'test_temp_project']);
      expect(code, equals(0));

      // Verify files generated
      expect(File('test_temp_project/pubspec.yaml').existsSync(), isTrue);
      expect(File('test_temp_project/bin/server.dart').existsSync(), isTrue);
      expect(File('test_temp_project/Dockerfile').existsSync(), isTrue);
      expect(File('test_temp_project/README.md').existsSync(), isTrue);
      expect(File('test_temp_project/lib/src/presentation/controllers/health_controller.dart').existsSync(), isTrue);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('Make commands generate proper scaffolding files', () async {
      final runner = EndveinCommandRunner();

      // Test make:controller
      final cCode = await runner.run(['make:controller', 'Article']);
      expect(cCode, equals(0));
      final cFile = File('lib/src/presentation/controllers/article_controller.dart');
      expect(cFile.existsSync(), isTrue);

      // Test make:usecase
      final uCode = await runner.run(['make:usecase', 'GetArticle']);
      expect(uCode, equals(0));
      final uFile = File('lib/src/domain/use_cases/get_article_use_case.dart');
      expect(uFile.existsSync(), isTrue);

      // Test make:middleware
      final mCode = await runner.run(['make:middleware', 'AuditLog']);
      expect(mCode, equals(0));
      final mFile = File('lib/src/presentation/middlewares/audit_log_middleware.dart');
      expect(mFile.existsSync(), isTrue);

      // Clean up generated files and directories
      cFile.deleteSync();
      uFile.deleteSync();
      mFile.deleteSync();
      Directory('lib/src/presentation/controllers').deleteSync(recursive: true);
      Directory('lib/src/presentation/middlewares').deleteSync(recursive: true);
      Directory('lib/src/presentation').deleteSync(recursive: true);
      Directory('lib/src/domain/use_cases').deleteSync(recursive: true);
      Directory('lib/src/domain').deleteSync(recursive: true);
    });
  });
}
