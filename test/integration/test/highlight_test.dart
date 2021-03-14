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

  test('requests highlights with bool capability', () async {
    final server = StubServer(client, capabilities: {
      'documentHighlightProvider': true,
    });
    final callMade = Completer<void>();
    server.peer.registerMethod('textDocument/documentHighlight',
        (Parameters params) {
      callMade.complete();
      return [];
    });
    await server.initialized;
    expect(callMade.future, completes);
  });

  test('requests highlights with map capability', () async {
    final server = StubServer(client, capabilities: {
      'documentHighlightProvider': true,
    });
    final callMade = Completer<void>();
    server.peer.registerMethod('textDocument/documentHighlight',
        (Parameters params) {
      callMade.complete();
      return [];
    });
    await server.initialized;
    expect(callMade.future, completes);
  });
}
