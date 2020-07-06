import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:test/test.dart';

void main() {
  Vim vim;
  setUpAll(() async {
    vim = await Vim.start();
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":"false",'
        '})');
  });

  tearDownAll(() async {
    await vim.quit();
    final log = File(vim.name);
    print(await log.readAsString());
    await log.delete();
  });

  test('reports a failure to start', () async {
    await vim.edit('foo.txt');
    final messages = await vim.messages(1);
    expect(messages, ['[lsc:Error] Failed to initialize server "\'false\'".']);
  });
}
