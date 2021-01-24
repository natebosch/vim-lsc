import 'dart:async';

import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

void main() {
  TestBed testBed;
  Peer client;

  setUpAll(() async {
    testBed = await TestBed.setup();
  });

  setUp(() async {
    final nextClient = testBed.clients.first;
    await testBed.vim.edit('foo.txt');
    await testBed.vim.sendKeys(':LSClientEnable<cr>');
    client = await nextClient;
  });

  tearDown(() async {
    await testBed.vim.sendKeys(':LSClientDisable<cr>');
    await testBed.vim.sendKeys(':%bwipeout!<cr>');
    await client.done;
    client = null;
  });

  Future<void> testNoDidSave(Map<String, dynamic> capabilities) async {
    final server = StubServer(client, capabilities: capabilities)
      ..didSave.listen((_) {
        fail('Unexpected didSave');
      });

    await server.initialized;

    await server.didOpen.first;

    await testBed.vim.sendKeys(':w<cr>');

    await testBed.vim.sendKeys('iHello<esc>');
    await await server.didChange.first;
  }

  test('TextDocumentSyncKind instead of TextDocumentSyncOptions', () async {
    await testNoDidSave({'textDocumentSync': 1});
  });

  test('omitted sync key', () async {
    await testNoDidSave({
      'textDocumentSync': {'openClose': true, 'change': 1}
    });
  });

  test('include sync key', () async {
    final server = StubServer(client, capabilities: {
      'textDocumentSync': {'openClose': true, 'save': {}}
    });

    await server.initialized;

    await server.didOpen.first;

    await testBed.vim.sendKeys(':w<cr>');

    await server.didSave.first;
  });
}
