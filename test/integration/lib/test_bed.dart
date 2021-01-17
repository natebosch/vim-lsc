import 'dart:io';

import 'package:test/test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;

import 'vim_remote.dart';

class TestBed {
  final Vim vim;
  final Stream<Peer> clients;

  TestBed._(this.vim, this.clients);

  static Future<TestBed> setup(
      {Future<void> Function(Vim) beforeRegister}) async {
    final serverSocket = await ServerSocket.bind('localhost', 0);

    final clients = serverSocket.map((socket) {
      final client =
          Peer(lspChannel(socket, socket), onUnhandledError: (error, stack) {
        fail('Unhandled server error: $error');
      });
      addTearDown(() => client.done);
    }).asBroadcastStream();
    final vim = await Vim.start();
    await beforeRegister?.call(vim);
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":"localhost:${serverSocket.port}",'
        '"enabled":v:false,'
        '})');

    addTearDown(() async {
      await vim.quit();
      final log = File(vim.name);
      print(await log.readAsString());
      await log.delete();
      await serverSocket.close();
    });
    return TestBed._(vim, clients);
  }
}
