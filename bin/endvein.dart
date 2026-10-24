import 'dart:io';
import 'package:endvein/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  final runner = EndveinCommandRunner();
  final exitCode = await runner.run(args);
  exit(exitCode);
}
