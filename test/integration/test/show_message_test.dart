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
    await client.done;
    client = null;
  });

  test('Shows request menu', () async {
    final server = StubServer(client);
    await server.initialized;
    final response = server.peer.sendRequest('window/showMessageRequest', {
      'type': 3,
      'message': 'Pick one:',
      'actions': [
        {'title': 'A'},
        {'title': 'B'},
      ]
    });
    await testBed.vim.stdinWriteln('1');
    await testBed.vim.stdinWriteln('');
    expect(await response, {'title': 'A'});
  });
}
