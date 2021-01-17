import 'dart:io';

import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
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
    await testBed.vim.sendKeys(':LSClientDisable<cr>');
    await testBed.vim.sendKeys(':%bwipeout!<cr>');
    final file = File('foo.txt');
    if (await file.exists()) await file.delete();
    client = null;
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
