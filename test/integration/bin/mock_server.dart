import 'package:_test/mock_lsp.dart';
import 'package:lsp/lsp.dart';

void main() async {
  final server = await StdIOLanguageServer.start(MockLanguageServer());
  await server.onDone;
}
