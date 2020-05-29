import 'dart:io';
import 'dart:math';

class Vim {
  /// The `--servername` argument.
  final String name;
  final Process _process;

  static Future<Vim> start() async {
    final version = (await Process.run('vim', ['--version'])).stdout as String;
    assert(version.contains('+clientserver'));
    final name = 'DARTVIM-${Random().nextInt(4294967296)}';
    final process = await Process.start(
        'vim', ['--servername', name, '-u', 'vimrc', '-U', 'NONE', '-V$name'],
        mode: ProcessStartMode.detachedWithStdio);
    while (!await _isRunning(name)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return Vim._(name, process);
  }

  Vim._(this.name, this._process);

  /// Sends `:qall!` and waits for the process to exit.
  Future<void> quit() {
    _process.stdin.writeln(':qall!');
    return _process.stdout.drain();
  }

  /// Send [keys] as if they were press in the vim window.
  ///
  /// Use vim syntax for special keys, for isntance '<cr>' for enter or '<esc>'
  /// for excape.
  Future<void> sendKeys(String keys) async {
    await Process.run('vim', [..._serverNameArg, '--remote-send', keys]);
  }

  /// Evaluate [expression] as a vim expression.
  Future<String> expr(String expression) async {
    final result = await Process.run(
        'vim', [..._serverNameArg, '--remote-expr', expression]);
    final stdout = result.stdout as String;
    return stdout.endsWith('\n')
        ? stdout.substring(0, stdout.length - 1)
        : stdout;
  }

  Future<void> edit(String fileName) async {
    final result =
        await Process.run('vim', [..._serverNameArg, '--remote', fileName]);
    final exitCode = await result.exitCode;
    assert(exitCode == 0);
    final openFile = await expr('expand(\'%\')');
    assert(openFile == fileName);
  }

  /// Returns the last [count] messages from `:messages`.
  Future<List<String>> messages(int count) async {
    await sendKeys(':redir => vim_remote_messages<cr>');
    await sendKeys(':${count}messages<cr>');
    await sendKeys(':redir END<cr>');
    final output = await expr('vim_remote_messages');
    return output.split('\n').skip(2).toList();
  }

  /// The full content of the currently active buffer.
  Future<String> get currentBufferContent async => expr(r'getline(1, "$")');

  Iterable<String> get _serverNameArg => ['--servername', name];
}

Future<bool> _isRunning(String name) async {
  final result = await Process.run('vim', ['--serverlist']);
  final serverList = (result.stdout as String).split('\n');
  return serverList.contains(name);
}
