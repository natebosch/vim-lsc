import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';

class StubServer {
  final Peer peer;
  Future<Map<String, dynamic>> get initialization => _initialization.future;
  final _initialization = Completer<Map<String, dynamic>>();

  StubServer(this.peer, {Map<String, dynamic> capabilities = const {}}) {
    peer
      ..registerMethod('initialize', (Parameters p) {
        _initialization.complete(p.asMap.cast<String, dynamic>());
        return {'capabilities': capabilities};
      })
      ..registerMethod('initialized', (_) {
        _initialized.complete();
      })
      ..registerMethod('workspace/didChangeConfiguration', (_) {})
      ..registerMethod('textDocument/didClose', (_) {})
      ..registerMethod('textDocument/didOpen', _didOpen.add)
      ..registerMethod('textDocument/didChange', _didChange.add)
      ..registerMethod('textDocument/didSave', _didSave.add)
      ..registerMethod('shutdown', (_) {})
      ..registerMethod('exit', (_) {
        peer.close();
      });
  }
  Stream<Parameters> get didOpen => _didOpen.stream;
  final _didOpen = StreamController<Parameters>();

  Stream<Parameters> get didChange => _didChange.stream;
  final _didChange = StreamController<Parameters>();

  Stream<Parameters> get didSave => _didSave.stream;
  final _didSave = StreamController<Parameters>();

  Future<void> get initialized {
    peer.listen();
    return _initialized.future;
  }

  final _initialized = Completer<void>();
}
