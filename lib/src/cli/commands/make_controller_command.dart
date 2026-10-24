import 'dart:io';
import 'package:args/command_runner.dart';

class MakeControllerCommand extends Command<int> {
  @override
  final String name = 'make:controller';

  @override
  final String description = 'Generate a new Endvein BaseController class.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln('❌ Error: Missing controller name. Usage: endvein make:controller <Name>');
      return 64;
    }

    final rawName = rest.first.trim();
    final nameWithoutSuffix = rawName.endsWith('Controller')
        ? rawName.substring(0, rawName.length - 10)
        : rawName;
    final className = '${nameWithoutSuffix}Controller';
    final fileName = '${_toSnakeCase(nameWithoutSuffix)}_controller.dart';

    final dir = Directory('lib/src/presentation/controllers');
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

class $className extends BaseController {
  Future<void> index(EndveinContext ctx) async {
    ctx.sendJson({
      'controller': '$className',
      'action': 'index',
    });
  }

  Future<void> show(EndveinContext ctx) async {
    final id = ctx.param('id');
    ctx.sendJson({
      'controller': '$className',
      'action': 'show',
      'id': id,
    });
  }
}
''');

    stdout.writeln('✅ Generated controller: ${file.path}');
    return 0;
  }

  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'(?<=[a-z])[A-Z]'),
      (Match m) => '_${m.group(0)}',
    ).toLowerCase();
  }
}
