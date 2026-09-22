import 'dart:io';

/// Terminal output. Colour and verbosity are configurable.
class Logger {
  Logger({
    this.color = true,
    this.verbose = false,
    IOSink? sink,
    IOSink? errSink,
  })  : _sink = sink ?? stdout,
        // Errors go to stderr, but the sink is injectable so tests can
        // capture them. Passing `sink` without `errSink` sends both to the
        // same place, which is what a test wants.
        _errSink = errSink ?? sink ?? stderr;

  final bool color;
  final bool verbose;
  final IOSink _sink;
  final IOSink _errSink;

  static const _red = '\x1B[0;31m';
  static const _green = '\x1B[0;32m';
  static const _yellow = '\x1B[1;33m';
  static const _blue = '\x1B[0;34m';
  static const _dim = '\x1B[2m';
  static const _reset = '\x1B[0m';

  String _paint(String code, String text) => color ? '$code$text$_reset' : text;

  void info(String m) => _sink.writeln('${_paint(_blue, '[deploykit]')} $m');
  void ok(String m) => _sink.writeln('${_paint(_green, '✓')} $m');
  void warn(String m) => _sink.writeln('${_paint(_yellow, '!')} $m');
  void err(String m) => _errSink.writeln('${_paint(_red, '✗')} $m');

  /// Only shown with `--verbose` — the commands being run, for example.
  void detail(String m) {
    if (verbose) _sink.writeln(_paint(_dim, '  $m'));
  }

  void blank() => _sink.writeln();
}
