import 'dart:async';
import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:test/test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart'
    show lspChannel, WorkspaceEdit, TextEdit, Range, Position;

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

  test('edit of entire file', () async {
    final renameDone = Completer<void>();
    client
      ..registerLifecycleMethods({})
      ..registerMethod('textDocument/rename', (Parameters params) {
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
      })
      ..listen();
    await vim.sendKeys('ifoo<cr>foo<esc>');
    await vim.sendKeys(':LSClientRename \'bar\'<cr>');
    await renameDone;
    await Future.delayed(const Duration(milliseconds: 100));
    expect(await vim.expr(r'getline(1, "$")'), 'bar\nbar');
  }, skip: 'https://github.com/natebosch/vim-lsc/issues/317');
}

extension LSP on Peer {
  void registerLifecycleMethods(Map<String, dynamic> capabilities) {
    registerMethod('initialize', (_) {
      return {'capabilities': capabilities};
    });
    registerMethod('initialized', (_) {});
    registerMethod('textDocument/didOpen', (_) {});
    registerMethod('textDocument/didChange', (_) {});
    registerMethod('shutdown', (_) {});
    registerMethod('exit', (_) {
      close();
    });
  }
}
