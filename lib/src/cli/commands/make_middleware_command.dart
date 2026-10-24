import 'dart:io';
import 'package:args/command_runner.dart';

class MakeMiddlewareCommand extends Command<int> {
  @override
  final String name = 'make:middleware';

  @override
  final String description = 'Generate a new EndveinMiddleware function.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln('❌ Error: Missing middleware name. Usage: endvein make:middleware <Name>');
      return 64;
    }

    final rawName = rest.first.trim();
    final nameWithoutSuffix = rawName.endsWith('Middleware')
        ? rawName.substring(0, rawName.length - 10)
        : rawName;
    final functionName = '${nameWithoutSuffix[0].toLowerCase()}${nameWithoutSuffix.substring(1)}Middleware';
    final fileName = '${_toSnakeCase(nameWithoutSuffix)}_middleware.dart';

    final dir = Directory('lib/src/presentation/middlewares');
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

/// Custom middleware: $functionName
EndveinMiddleware $functionName() {
  return (EndveinContext ctx, NextFunction next) async {
    // 1. Pre-processing before handler execution
    final start = DateTime.now();

    // 2. Execute downstream handler or next middleware
    final response = await next();

    // 3. Post-processing
    final duration = DateTime.now().difference(start);
    ctx.setHeader('X-Response-Time', '\${duration.inMilliseconds}ms');

    return response;
  };
}
''');

    stdout.writeln('✅ Generated middleware: ${file.path}');
    return 0;
  }

  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'(?<=[a-z])[A-Z]'),
      (Match m) => '_${m.group(0)}',
    ).toLowerCase();
  }
}
