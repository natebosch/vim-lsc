import 'dart:async';
import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;
import 'package:test/test.dart';

void main() {
  group('initially disabled', () {
    Stream<Peer> clients;
    ServerSocket serverSocket;
    Vim vim;
    Peer client;

    setUpAll(() async {
      serverSocket = await ServerSocket.bind('localhost', 0);

      clients = serverSocket.map((socket) {
        return Peer(lspChannel(socket, socket),
            onUnhandledError: (error, stack) {
          fail('Unhandled server error: $error');
        });
      }).asBroadcastStream();
      vim = await Vim.start();

      // Register after a file is open
      await vim.edit('foo.txt');
      await vim.expr('RegisterLanguageServer("text", {'
          '"command":"localhost:${serverSocket.port}",'
          '"enabled":v:false,'
          '})');
    });
    tearDownAll(() async {
      await vim.quit();
      final log = File(vim.name);
      print(await log.readAsString());
      await log.delete();
      await serverSocket.close();
    });

    test('waits to start until explicitly enabled', () async {
      expect(await vim.expr('lsc#server#status(\'text\')'), 'disabled');
      final nextClient = clients.first;
      await vim.sendKeys(':LSClientEnable<cr>');
      client = await nextClient;
      final server = StubServer(client);
      await server.initialized;
    });

    tearDown(() async {
      await vim.sendKeys(':LSClientDisable<cr>');
      await vim.sendKeys(':%bwipeout!<cr>');
      final file = File('foo.txt');
      if (await file.exists()) await file.delete();
      await client?.done;
      client = null;
    });
  });
}
