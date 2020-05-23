import 'dart:async';
import 'dart:io';

import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;
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

  Future<void> testNoDidSave(Map<String, dynamic> capabilities) async {
    final didOpen = Completer<Parameters>();
    final didSave = Completer<Parameters>()
      ..future.then((_) {
        fail('Unexpected didSave');
      });
    final didChange = Completer<Parameters>();
    client
      ..registerLifecycleMethods(capabilities)
      ..registerMethod(
          'textDocument/didOpen', (params) => didOpen.complete(params))
      ..registerMethod(
          'textDocument/didSave', (params) => didSave.complete(params))
      ..registerMethod(
          'textDocument/didChange', (params) => didChange.complete(params))
      ..listen();

    await didOpen.future;

    await vim.sendKeys(':w<cr>');

    await vim.sendKeys('iHello<esc>');
    await didChange.future;
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
    final didOpen = Completer<Parameters>();
    final didSave = Completer<Parameters>();
    client
      ..registerLifecycleMethods({
        'textDocumentSync': {'openClose': true, 'save': {}}
      })
      ..registerMethod(
          'textDocument/didOpen', (params) => didOpen.complete(params))
      ..registerMethod(
          'textDocument/didSave', (params) => didSave.complete(params))
      ..listen();

    await didOpen.future;

    await vim.sendKeys(':w<cr>');

    await didSave.future;
  });
}

extension LSP on Peer {
  void registerLifecycleMethods(Map<String, dynamic> capabilities) {
    registerMethod('initialize', (params) {
      return {'capabilities': capabilities};
    });
    registerMethod('initialized', (_) {});
    registerMethod('shutdown', (_) {});
    registerMethod('exit', (_) {
      close();
    });
  }
}
