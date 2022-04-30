import 'dart:async';

import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show CompletionItem;
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
    await testBed.vim.sendKeys('<C-\\><C-N>');
    await testBed.vim.sendKeys(':LSClientDisable<cr>');
    await testBed.vim.sendKeys(':%bwipeout!<cr>');
    await client.done;
    client = null;
  });

  test('autocomplete on trigger', () async {
    final server = StubServer(client, capabilities: {
      'completionProvider': {
        'triggerCharacters': ['.']
      },
    });
    server.peer.registerMethod('textDocument/completion', (Parameters params) {
      return [
        CompletionItem((b) => b..label = 'abcd'),
        CompletionItem((b) => b..label = 'foo')
      ];
    });
    await server.initialized;
    await testBed.vim.sendKeys('ifoo.');
    await testBed.vim.waitForPopUpMenu();
    await testBed.vim.sendKeys('a<cr><esc>');
    expect(await testBed.vim.expr('getline(1)'), 'foo.abcd');
  });

  test('filter out trigger characters', () async {
    await testBed.vim
        .sendKeys(':let g:lsc_block_complete_triggers = ["{"]<cr>');
    final server = StubServer(client, capabilities: {
      'completionProvider': {
        'triggerCharacters': ['.', '{']
      },
    });
    var completeWasCalled = false;
    server.peer.registerMethod('textDocument/completion', (Parameters _) {
      // Thrown exception would be caught by JSON RPC.
      completeWasCalled = true;
    });
    await server.initialized;
    await testBed.vim.sendKeys('i{');
    await Future.delayed(const Duration(seconds: 1));
    expect(completeWasCalled, false);
  });

  test('autocomplete on 3 word characters', () async {
    final server = StubServer(client, capabilities: {
      'completionProvider': {'triggerCharacters': []},
    });
    server.peer.registerMethod('textDocument/completion', (Parameters params) {
      return [
        CompletionItem((b) => b..label = 'foobar'),
        CompletionItem((b) => b..label = 'fooother')
      ];
    });
    await server.initialized;
    await testBed.vim.sendKeys('ifoo');
    await testBed.vim.waitForPopUpMenu();
    await testBed.vim.sendKeys('b<cr><esc>');
    expect(await testBed.vim.expr('getline(1)'), 'foobar');
  });

  test('manual completion', () async {
    final server = StubServer(client, capabilities: {
      'completionProvider': {'triggerCharacters': []},
    });
    server.peer.registerMethod('textDocument/completion', (Parameters params) {
      return [
        CompletionItem((b) => b..label = 'foobar'),
        CompletionItem((b) => b..label = 'fooother')
      ];
    });
    await server.initialized;
    await testBed.vim.sendKeys('if<c-x><c-u>');
    await testBed.vim.waitForPopUpMenu();
    await testBed.vim.sendKeys('<cr><esc>');
    expect(await testBed.vim.expr('getline(1)'), 'foobar');
  });
}

extension PopUp on Vim {
  Future<void> waitForPopUpMenu() async {
    final until = DateTime.now().add(const Duration(seconds: 5));
    while (await this.expr('pumvisible()') != '1') {
      await Future.delayed(const Duration(milliseconds: 50));
      if (DateTime.now().isAfter(until)) {
        throw StateError('Pop up menu is not visible');
      }
    }
  }
}
