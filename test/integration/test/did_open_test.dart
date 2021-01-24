import 'package:async/async.dart';
import 'package:_test/stub_lsp.dart';
import 'package:_test/test_bed.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

void main() {
  group('Registering a new file type', () {
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
      await client.done;
      client = null;
    });

    test('sends didOpen for already open files', () async {
      final server = StubServer(client);
      final opens = StreamQueue(server.didOpen);

      await server.initialized;
      await opens.next;

      await testBed.vim.edit('foo.py');
      await testBed.vim.expr('RegisterLanguageServer("python", "Test Server")');
      final nextOpen = await opens.next;
      expect(nextOpen['textDocument']['uri'].asString, endsWith('foo.py'));
    });
  });
}
