import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:test/test.dart';

void main() {
  group('initially disabled', () {
    TestBed testBed;

    setUpAll(() async {
      testBed = await TestBed.setup(beforeRegister: (vim) async {
        await vim.edit('foo.txt');
      });
    });

    test('waits to start until explicitly enabled', () async {
      expect(await testBed.vim.expr('lsc#server#status(\'text\')'), 'disabled');
      final nextClient = testBed.clients.first;
      await testBed.vim.sendKeys(':LSClientEnable<cr>');
      final client = await nextClient;
      final server = StubServer(client);
      await server.initialized;
    });

    tearDown(() async {
      await testBed.vim.sendKeys(':LSClientDisable<cr>');
      await testBed.vim.sendKeys(':%bwipeout!<cr>');
      final file = File('foo.txt');
      if (await file.exists()) await file.delete();
    });
  });
}
