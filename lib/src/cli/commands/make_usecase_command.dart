import 'dart:io';
import 'package:args/command_runner.dart';

class MakeUseCaseCommand extends Command<int> {
  @override
  final String name = 'make:usecase';

  @override
  final String description = 'Generate a Clean Architecture UseCase class.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln('❌ Error: Missing usecase name. Usage: endvein make:usecase <Name>');
      return 64;
    }

    final rawName = rest.first.trim();
    final nameWithoutSuffix = rawName.endsWith('UseCase')
        ? rawName.substring(0, rawName.length - 7)
        : rawName;
    final className = '${nameWithoutSuffix}UseCase';
    final fileName = '${_toSnakeCase(nameWithoutSuffix)}_use_case.dart';

    final dir = Directory('lib/src/domain/use_cases');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final file = File('${dir.path}/$fileName');
    if (file.existsSync()) {
      stderr.writeln('⚠️ Warning: File "${file.path}" already exists.');
      return 1;
    }

    file.writeAsStringSync('''
import 'package:endvein/endvein.dart';

class ${className}Params {
  final String id;
  const ${className}Params({required this.id});
}

class $className implements UseCase<String, ${className}Params> {
  @override
  Future<Result<String, Exception>> call(${className}Params params) async {
    try {
      // Execute business logic
      return Success('Result for \${params.id}');
    } catch (e) {
      return Failure(Exception('Failed to execute $className: \$e'));
    }
  }
}
''');

    stdout.writeln('✅ Generated use case: ${file.path}');
    return 0;
  }

  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'(?<=[a-z])[A-Z]'),
      (Match m) => '_${m.group(0)}',
    ).toLowerCase();
  }
}
