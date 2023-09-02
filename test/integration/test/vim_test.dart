import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group(Vim, () {
    Vim vim;
    setUpAll(() async {
      vim = await Vim.start();
      final serverPath = p.absolute('bin', 'stub_server.dart');
      await vim.expr('RegisterLanguageServer("text","dart $serverPath")');
    });

    tearDownAll(() async {
      await vim.quit();
      final log = File(vim.name);
      print(await log.readAsString());
      await log.delete();
    });

    test('evaluates expressions', () async {
      final result = await vim.expr('version');
      expect(int.tryParse(result), isNotNull);
    });

    test('sends keys', () async {
      await vim.sendKeys('iHello there!<esc>');
      expect(await vim.currentBufferContent, 'Hello there!');
    });

    test('loads plugin', () async {
      final result = await vim.expr('exists(\':LSClientGoToDefinition\')');
      expect(result, '2');
    });

    test('loads plugin', () async {
      final result = await vim.expr('exists(\':LSClientGoToDeclaration\')');
      expect(result, '1');
    });

    test('opens files, has filetype detection', () async {
      await vim.edit('foo.txt');
      expect(await vim.expr('&ft'), 'text');
    });

    group('open file', () {
      setUpAll(() async {
        await vim.edit('foo.txt');
      });

      tearDownAll(() async {
        await vim.sendKeys(':%bd!<cr>');
      });

      test('sets filetype', () async {
        expect(await vim.expr('&ft'), 'text');
      });

      test('starts language server', () async {
        while (await vim.expr('lsc#server#status(\'text\')') != 'running') {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });
    });
  });
}
