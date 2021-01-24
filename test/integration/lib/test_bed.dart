import 'dart:io';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'vim_remote.dart';

class TestBed {
  final Vim vim;
  final Stream<Peer> clients;

  TestBed._(this.vim, this.clients);

  static Future<TestBed> setup(
      {Future<void> Function(Vim) beforeRegister, String config = ''}) async {
    final serverSocket = await ServerSocket.bind('localhost', 0);

    final clients = serverSocket
        .map((socket) => Peer(lspChannel(socket, socket),
            onUnhandledError: (error, stack) =>
                fail('Unhandled server error: $error')))
        .asBroadcastStream();
    final vim = await Vim.start(workingDirectory: d.sandbox);
    await beforeRegister?.call(vim);
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":"localhost:${serverSocket.port}",'
        '"name":"Test Server",'
        '"enabled":v:false,'
        '$config'
        '})');

    addTearDown(() async {
      await vim.quit();
      print(await d.file(vim.name).io.readAsString());
      await serverSocket.close();
    });
    return TestBed._(vim, clients);
  }
}
