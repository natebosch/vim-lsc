import 'dart:convert';
import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/vim_remote.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:lsp/lsp.dart' show lspChannel;
import 'package:stream_channel/stream_channel.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:test/test.dart';

void main() {
  Stream<Peer> clients;
  Vim vim;
  Peer client;

  setUpAll(() async {
    final serverSocket = await ServerSocket.bind('localhost', 0);
    addTearDown(serverSocket.close);

    clients = serverSocket.map((socket) {
      final channel = lspChannel(socket.tap((l) {
        print('From Vim: ' + utf8.decode(l));
      }), socket);
      return Peer(
          StreamChannel(channel.stream.tap((m) {
            print('LSP from Vim: $m');
          }), channel.sink), onUnhandledError: (error, _) {
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
    print('Tearing down. Disabling LSC');
    await vim.sendKeys(':LSClientDisable<cr>');
    print('wiping out buffers');
    await vim.sendKeys(':%bwipeout!<cr>');
    final file = File('foo.txt');
    print('Checking for file to delete');
    if (await file.exists()) await file.delete();
    print('Waiting for client to close');
    await client.done;
    print('Done');
    client = null;
  });

  tearDownAll(() async {
    await vim.quit();
    final log = File(vim.name);
    print(await log.readAsString());
    await log.delete();
  });

  test('can send workspace configuration', () async {
    client
      ..registerLifecycleMethods({})
      ..listen();

    final response = await client.sendRequest('workspace/configuration', {
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
    print('Waiting for response');
    final response = await server.peer.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo'},
        {'section': 'other'}
      ]
    });
    print('Got response: $response');
    expect(response, [
      {'baz': 'bar'},
      'something'
    ]);
  }, solo: true);

  test('can send nested config with dotted keys', () async {
    client
      ..registerLifecycleMethods({})
      ..listen();

    final response = await client.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo.baz'},
      ]
    });
    expect(response, ['bar']);
  });

  test('handles missing keys', () async {
    client
      ..registerLifecycleMethods({})
      ..listen();

    final response = await client.sendRequest('workspace/configuration', {
      'items': [
        {'section': 'foo.missing'},
        {'section': 'missing'}
      ]
    });
    expect(response, [null, null]);
  });
}
