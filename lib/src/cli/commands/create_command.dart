import 'dart:io';
import 'package:args/command_runner.dart';

class CreateCommand extends Command<int> {
  @override
  final String name = 'create';

  @override
  final String description = 'Create a new Endvein project with Clean Architecture scaffolding.';

  CreateCommand() {
    argParser.addOption(
      'template',
      abbr: 't',
      defaultsTo: 'standard',
      allowed: ['standard', 'minimal'],
      help: 'Project template to scaffold.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln('❌ Error: Missing project name. Usage: endvein create <project_name>');
      return 64;
    }

    final projectName = rest.first.trim().toLowerCase().replaceAll('-', '_');
    final targetDir = Directory(projectName);

    if (targetDir.existsSync()) {
      stderr.writeln('❌ Error: Directory "$projectName" already exists.');
      return 1;
    }

    stdout.writeln('⚡ Scaffolding Endvein project: $projectName...');

    // 1. Create directories
    final dirs = [
      '$projectName/bin',
      '$projectName/lib/src/domain/models',
      '$projectName/lib/src/domain/use_cases',
      '$projectName/lib/src/data/repositories',
      '$projectName/lib/src/presentation/controllers',
      '$projectName/lib/src/presentation/middlewares',
      '$projectName/test',
    ];

    for (final d in dirs) {
      Directory(d).createSync(recursive: true);
    }

    // 2. pubspec.yaml
    File('$projectName/pubspec.yaml').writeAsStringSync('''
name: $projectName
description: High-performance backend service powered by Endvein.
version: 1.0.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  endvein: ^0.2.0

dev_dependencies:
  lints: ^3.0.0
  test: ^1.24.0
''');

    // 3. bin/server.dart
    File('$projectName/bin/server.dart').writeAsStringSync('''
import 'package:endvein/endvein.dart';
import '../lib/src/presentation/controllers/health_controller.dart';

void main() async {
  final cluster = EndveinCluster(
    host: '0.0.0.0',
    port: 8080,
    engineMode: EngineMode.rawSocket, // ⚡ Default ultra-high-throughput 196k+ RPS
    routerFactory: () {
      final router = EndveinRouter();

      // Middlewares
      router.use(cors());
      router.use(securityHeaders());
      router.use(logger());

      // Routes
      final healthCtrl = HealthController();
      router.get('/health', healthCtrl.check);

      router.get('/', (ctx) {
        ctx.sendJson({
          'framework': 'Endvein',
          'status': 'online',
          'version': '1.0.0',
        });
      });

      return router;
    },
  );

  await cluster.run();
}
''');

    // 4. lib/src/presentation/controllers/health_controller.dart
    File('$projectName/lib/src/presentation/controllers/health_controller.dart').writeAsStringSync('''
import 'package:endvein/endvein.dart';

class HealthController extends BaseController {
  void check(EndveinContext ctx) {
    ctx.sendJson({
      'status': 'healthy',
      'uptime': DateTime.now().toIso8601String(),
    });
  }
}
''');

    // 5. Dockerfile (Multi-stage AOT)
    File('$projectName/Dockerfile').writeAsStringSync('''
# Stage 1: Build AOT Native Binary
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Minimal Production Image (Scratch / Distroless)
FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/bin/server /app/server
EXPOSE 8080
CMD ["/app/server"]
''');

    // 6. README.md
    File('$projectName/README.md').writeAsStringSync('''
# $projectName

High-performance backend service built with [Endvein](https://github.com/nasrulalawy/endvein).

## Quick Start
```bash
# Get dependencies
dart pub get

# Run in Development mode
dart run bin/server.dart

# Compile to High-Speed AOT Binary
dart compile exe bin/server.dart -o server
./server
```
''');

    stdout.writeln('✅ Successfully created project $projectName!');
    stdout.writeln('👉 Next steps:');
    stdout.writeln('   cd $projectName');
    stdout.writeln('   dart pub get');
    stdout.writeln('   dart run bin/server.dart');
    return 0;
  }
}
