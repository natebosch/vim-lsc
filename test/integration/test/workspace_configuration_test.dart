import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;
import 'package:test/test.dart';

void main() {
  Stream<Peer> clients;
  Vim vim;
  Peer client;

  setUpAll(() async {
    final serverSocket = await ServerSocket.bind('localhost', 0);
    addTearDown(serverSocket.close);

    clients = serverSocket.map((socket) {
      return Peer(lspChannel(socket, socket), onUnhandledError: (error, _) {
        fail('Unhandled server error: $error');
      });
    }).asBroadcastStream();
    vim = await Vim.start();
    await vim.expr('RegisterLanguageServer("text", {'
        '"command":"localhost:${serverSocket.port}",'
        '"workspace_config":{"foo":{"baz":"bar"},"other":"something"},'
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
  });

  test('can send workspace configuration', () async {
    final server = StubServer(client);
    await server.initialized;

    final response = await server.peer.sendRequest('workspace/configuration', {
      'items': [{}]
    });
    expect(response, [
      {
        'foo': {'baz': 'bar'},
        'other': 'something',
      }
    ]);
  });

  test('can send multiple configurations', () async {
    final server = StubServer(client);
    await server.initialized;

    final response = await server.peer.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo'},
        {'section': 'other'}
      ]
    });
    expect(response, [
      {'baz': 'bar'},
      'something'
    ]);
  });

  test('can send nested config with dotted keys', () async {
    final server = StubServer(client);
    await server.initialized;

    final response = await server.peer.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo.baz'},
      ]
    });
    expect(response, ['bar']);
  });

  test('handles missing keys', () async {
    final server = StubServer(client);
    await server.initialized;

    final response = await client.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo.missing'},
        {'section': 'missing'}
      ]
    });
    expect(response, [null, null]);
  });
}
