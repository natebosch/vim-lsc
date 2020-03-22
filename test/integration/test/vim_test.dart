@Timeout(Duration(seconds: 30))

import 'package:_test/vim_remote.dart';
import 'package:test/test.dart';

void main() {
  group(Vim, () {
    Vim vim;
    setUpAll(() async {
      vim = await Vim.start();
    });

    tearDownAll(() async {
      await vim.quit();
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
          print('Status: ${await vim.expr('lsc#server#status(\'text\')')}');
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });
    });
  });
}
