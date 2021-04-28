import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('WorkspaceRoot configured', () {
    TestBed testBed;
    Peer client;

    setUpAll(() async {
      await d.dir('workspaces', [
        d.dir('foo', [
          d.file('makefile'),
          d.dir('lib', [d.file('foo.txt')])
        ]),
        d.dir('bar', [
          d.file('makefile'),
          d.dir('lib', [d.file('bar.txt')])
        ])
      ]).create();
      testBed = await TestBed.setup(
        config: '"WorkspaceRoot": lsc#workspace#byMarker(["lib/"]),',
      );
    });

    setUp(() async {
      final nextClient = testBed.clients.first;
      await testBed.vim.edit('workspaces/foo/lib/foo.txt');
      await testBed.vim.sendKeys(':LSClientEnable<cr>');
      client = await nextClient;
    });

    tearDown(() async {
      await testBed.vim.sendKeys(':LSClientDisable<cr>');
      await testBed.vim.sendKeys(':%bwipeout!<cr>');
      await client.done;
      client = null;
    });

    test('uses root for initialization', () async {
      final server = StubServer(client);

      await server.initialized;
      final initialization = await server.initialization;
      expect(initialization['capabilities']['workspace']['workspaceFolders'],
          true);
      expect(initialization['workspaceFolders'], [
        {
          'uri': d.dir('workspaces/foo').io.uri.toString(),
          'name': 'workspaces/foo/'
        }
      ]);
    });

    test('does not send notificaiton without capability', () async {
      final server = StubServer(client, capabilities: {
        'workspace': {
          'workspaceFolders': {
            'supported': true,
            'changeNotifications': false,
          }
        }
      });

      server.peer.registerMethod('workspace/didChangeWorkspaceFolders',
          (Parameters p) {
        fail('Unexpected call to didChangeWorkspaceFolders');
      });
      await server.initialized;

      await testBed.vim.edit('workspaces/bar/lib/bar.txt');

      await Future.delayed(const Duration(milliseconds: 10));
    });

    test('sends notifications with string capability', () async {
      final server = StubServer(client, capabilities: {
        'workspace': {
          'workspaceFolders': {
            'supported': true,
            'changeNotifications': 'something',
          }
        }
      });
      final changeController = StreamController<Map<String, dynamic>>();
      final changeEvents = StreamQueue(changeController.stream);
      server.peer.registerMethod('workspace/didChangeWorkspaceFolders',
          (Parameters p) {
        changeController.add(p['event'].asMap.cast<String, dynamic>());
      });

      await server.initialized;

      await testBed.vim.edit('workspaces/bar/lib/bar.txt');

      final change = await changeEvents.next;
      expect(change['removed'], isEmpty);
      expect(change['added'], [
        {
          'uri': d.dir('workspaces/bar').io.uri.toString(),
          'name': 'workspaces/bar/'
        }
      ]);
    });

    test('sends notifications with bool capability', () async {
      final server = StubServer(client, capabilities: {
        'workspace': {
          'workspaceFolders': {
            'supported': true,
            'changeNotifications': true,
          }
        }
      });

      final changeController = StreamController<Map<String, dynamic>>();
      final changeEvents = StreamQueue(changeController.stream);
      server.peer.registerMethod('workspace/didChangeWorkspaceFolders',
          (Parameters p) {
        changeController.add(p['event'].asMap.cast<String, dynamic>());
      });

      await server.initialized;

      await testBed.vim.edit('workspaces/bar/lib/bar.txt');

      final change = await changeEvents.next;
      expect(change['removed'], isEmpty);
      expect(change['added'], [
        {'uri': d.dir('workspaces/bar').io.uri.toString(), 'name': anything}
      ]);
    });
  });

  group('WorkspaceRoot throws', () {
    TestBed testBed;
    Peer client;

    setUpAll(() async {
      testBed = await TestBed.setup(
          beforeRegister: (vim) async {
            await vim.sendKeys(':function! ThrowingRoot(path) abort<cr>');
            await vim.sendKeys('throw "sad"<cr>');
            await vim.sendKeys('endfunction<cr>');
            await vim.sendKeys('<cr>');
          },
          config: '"WorkspaceRoot":function("ThrowingRoot"),');
      await d.dir('workspaces', [
        d.dir('foo', [
          d.file('makefile'),
          d.dir('lib', [d.file('foo.txt')])
        ]),
        d.dir('bar', [
          d.file('makefile'),
          d.dir('lib', [d.file('bar.txt')])
        ])
      ]).create();
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
      await client.done;
      client = null;
    });

    test('does not advertise capability', () async {
      final server = StubServer(client);

      await server.initialized;
      final initialization = await server.initialization;
      expect(initialization['capabilities']['workspace']['workspaceFolders'],
          false);
      final messages = await testBed.vim.messages(1);
      expect(messages, [
        '[lsc:Error] Disabling workspace roots due to error: \'sad\'',
      ]);
    });
  });

  group('No WorkspaceRoot configured', () {
    TestBed testBed;
    Peer client;

    setUpAll(() async {
      testBed = await TestBed.setup();
      await d.dir('workspaces', [
        d.dir('foo', [
          d.file('makefile'),
          d.dir('lib', [d.file('foo.txt')])
        ]),
        d.dir('bar', [
          d.file('makefile'),
          d.dir('lib', [d.file('bar.txt')])
        ])
      ]).create();
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
      await client.done;
      client = null;
    });

    test('does not advertise capability', () async {
      final server = StubServer(client);

      await server.initialized;
      final initialization = await server.initialization;
      expect(initialization['capabilities']['workspace']['workspaceFolders'],
          false);
    });
  });
}
