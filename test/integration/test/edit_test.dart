import 'dart:async';
import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:test/test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show WorkspaceEdit, TextEdit, Range, Position;

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

  test('edit of entire file', () async {
    final renameDone = Completer<void>();
    final server = StubServer(client);
    server.peer.registerMethod('textDocument/rename', (Parameters params) {
      renameDone.complete();
      final uri = params['textDocument']['uri'].asString;
      return WorkspaceEdit((b) => b
        ..changes = {
          uri: [
            TextEdit((b) => b
              ..newText = 'bar\nbar\n'
              ..range = Range((b) => b
                ..start = Position((b) => b
                  ..line = 0
                  ..character = 0)
                ..end = Position((b) => b
                  ..line = 2
                  ..character = 0)))
          ]
        });
    });
    await server.initialized;
    await testBed.vim.sendKeys('ifoo<cr>foo<esc>');
    await testBed.vim.sendKeys(':LSClientRename \'bar\'<cr>');
    await renameDone;
    await Future.delayed(const Duration(milliseconds: 100));
    expect(await testBed.vim.expr(r'getline(1, "$")'), 'bar\nbar\n');
  });
}
