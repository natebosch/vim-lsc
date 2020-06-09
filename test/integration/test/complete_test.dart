import 'dart:async';
import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel, CompletionItem;
import 'package:test/test.dart';

void main() {
  Stream<Peer> clients;
  ServerSocket serverSocket;
  Vim vim;
  Peer client;

  setUpAll(() async {
    serverSocket = await ServerSocket.bind('localhost', 0);

    clients = serverSocket.map((socket) {
      return Peer(lspChannel(socket, socket), onUnhandledError: (error, stack) {
        fail('Unhandled server error: $error');
      });
    }).asBroadcastStream();
    vim = await Vim.start();
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":"localhost:${serverSocket.port}",'
        '"enabled":v:false,'
        '})');
  });

  setUp(() async {
    final nextClient = clients.first;
    await vim.edit('foo.txt');
    await vim.sendKeys(':LSClientEnable<cr>');
    client = await nextClient;
  });

  tearDown(() async {
    await vim.sendKeys(':LSClientDisable<cr>');
    await vim.sendKeys(':%bwipeout!<cr>');
    final file = File('foo.txt');
    if (await file.exists()) await file.delete();
    await client.done;
    client = null;
  });

  tearDownAll(() async {
    await vim.quit();
    final log = File(vim.name);
    print(await log.readAsString());
    await log.delete();
    await serverSocket.close();
  });

  test('autocomplete on trigger', () async {
    client
      ..registerLifecycleMethods({
        'completionProvider': {
          'triggerCharacters': ['.']
        },
      })
      ..registerMethod('textDocument/didOpen', (_) {})
      ..registerMethod('textDocument/didChange', (_) {})
      ..registerMethod('textDocument/completion', (Parameters params) {
        return [
          CompletionItem((b) => b..label = 'abcd'),
          CompletionItem((b) => b..label = 'foo')
        ];
      })
      ..listen();
    await vim.sendKeys('ifoo.');
    await vim.waitForPopUpMenu();
    await vim.sendKeys('a<c-n><esc><esc>');
    expect(await vim.expr('getline(1)'), 'foo.abcd');
  });

  test('autocomplete on 3 word characters', () async {
    client
      ..registerLifecycleMethods({
        'completionProvider': {'triggerCharacters': []},
      })
      ..registerMethod('textDocument/didOpen', (_) {})
      ..registerMethod('textDocument/didChange', (_) {})
      ..registerMethod('textDocument/completion', (Parameters params) {
        return [
          CompletionItem((b) => b..label = 'foobar'),
          CompletionItem((b) => b..label = 'fooother')
        ];
      })
      ..listen();
    await vim.sendKeys('ifoo');
    await vim.waitForPopUpMenu();
    await vim.sendKeys('b<c-n><esc><esc>');
    expect(await vim.expr('getline(1)'), 'foobar');
  });

  test('manual completion', () async {
    client
      ..registerLifecycleMethods({
        'completionProvider': {'triggerCharacters': []},
      })
      ..registerMethod('textDocument/didOpen', (_) {})
      ..registerMethod('textDocument/didChange', (_) {})
      ..registerMethod('textDocument/completion', (Parameters params) {
        return [
          CompletionItem((b) => b..label = 'foobar'),
          CompletionItem((b) => b..label = 'fooother')
        ];
      })
      ..listen();
    await vim.sendKeys('if<c-x><c-u>');
    await vim.waitForPopUpMenu();
    await vim.sendKeys('<c-n><esc><esc>');
    expect(await vim.expr('getline(1)'), 'foobar');
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

extension LSP on Peer {
  void registerLifecycleMethods(Map<String, dynamic> capabilities) {
    registerMethod('initialize', (_) {
      return {'capabilities': capabilities};
    });
    registerMethod('initialized', (_) {});
    registerMethod('shutdown', (_) {});
    registerMethod('exit', (_) {
      close();
    });
  }
}
