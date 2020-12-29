import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';

extension LSP on Peer {
  void registerLifecycleMethods(
    Map<String, dynamic> capabilities, {
    void Function(Parameters) didOpen,
    void Function(Parameters) didChange,
    void Function(Parameters) didSave,
  }) {
    registerMethod('initialize', (_) {
      return {'capabilities': capabilities};
    });
    registerMethod('initialized', (_) {});
    registerMethod('workspace/didChangeConfiguration', (_) {});
    registerMethod('textDocument/didOpen', _cast(didOpen) ?? _ignore);
    registerMethod('textDocument/didChange', _cast(didChange) ?? _ignore);
    registerMethod('textDocument/didSave', _cast(didSave) ?? _ignore);
    registerMethod('shutdown', (_) {});
    registerMethod('exit', (_) {
      close();
    });
  }
}

void Function(dynamic) _cast(void Function(Parameters) f) =>
    f == null ? null : (p) => f(p as Parameters);

void _ignore(dynamic _) {}

class StubServer {
  final Peer peer;

  StubServer(this.peer) {
    peer
      ..registerMethod('initialize', (_) {
        return {'capabilities': {}};
      })
      ..registerMethod('initialized', (_) {
        _initialized.complete();
      })
      ..registerMethod('workspace/didChangeConfiguration', (_) {})
      ..registerMethod('textDocument/didOpen', _ignore)
      ..registerMethod('textDocument/didChange', _ignore)
      ..registerMethod('textDocument/didSave', _ignore)
      ..registerMethod('shutdown', (_) {})
      ..registerMethod('exit', (_) {
        peer.close();
      })
      ..listen();
  }

  Future<void> get initialized => _initialized.future;
  final _initialized = Completer<void>();
}
