import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:test/test.dart';

void main() {
  Vim vim;
  setUp(() async {
    vim = await Vim.start();
  });

  tearDown(() async {
    await vim.quit();
    final log = File(vim.name);
    print(await log.readAsString());
    await log.delete();
  });

  test('emits stderr by default', () async {
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":["sh", "-c", "echo messagestderr >&2"],'
        '"name":"some server"'
        '})');
    await vim.edit('foo.txt');
    while (await vim.expr('lsc#server#status(\'text\')') != 'failed') {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final messages = await vim.messages(2);
    expect(messages, [
      '[lsc:Error] StdErr from some server: messagestderr',
      '[lsc:Error] Failed to initialize server "some server". '
          'Failing command is: [\'sh\', \'-c\', \'echo messagestderr >&2\']'
    ]);
  });

  test('suppresses stderr', () async {
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":["sh", "-c", "echo messagestderr >&2"],'
        '"name":"some server",'
        '"suppress_stderr": v:true,'
        '})');
    await vim.edit('foo.txt');
    while (await vim.expr('lsc#server#status(\'text\')') != 'failed') {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final messages = await vim.messages(2);
    expect(messages, [
      '"foo.txt" [New] --No lines in buffer--',
      '[lsc:Error] Failed to initialize server "some server". '
          'Failing command is: [\'sh\', \'-c\', \'echo messagestderr >&2\']'
    ]);
  });
}
