import 'dart:io';
import 'package:args/command_runner.dart';

import 'commands/create_command.dart';
import 'commands/make_controller_command.dart';
import 'commands/make_middleware_command.dart';
import 'commands/make_usecase_command.dart';

class EndveinCommandRunner extends CommandRunner<int> {
  EndveinCommandRunner()
      : super(
          'endvein',
          '⚡ Endvein CLI - Ultra-High-Throughput Dart Backend Scaffolding Tool.',
        ) {
    addCommand(CreateCommand());
    addCommand(MakeControllerCommand());
    addCommand(MakeUseCaseCommand());
    addCommand(MakeMiddlewareCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final exitCode = await super.run(args);
      return exitCode ?? 0;
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      stderr.writeln('');
      stderr.writeln(e.usage);
      return 64;
    } catch (e, stack) {
      stderr.writeln('❌ Unexpected error: $e\n$stack');
      return 1;
    }
  }
}
