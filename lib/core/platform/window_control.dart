import 'dart:io';

import 'package:flutter/services.dart';

/// The Linux runner's window (linux/runner/my_application.cc): bring it forward, and whether closing it only hides it
/// so reminders keep running. Elsewhere, and in tests, these do nothing.
class WindowControl {
  const WindowControl();
  static const _channel = MethodChannel('bahai_reader/window');

  Future<void> _call(String method, [Object? args]) async {
    if (!Platform.isLinux) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No runner channel (tests).
    } on PlatformException {
      // Ignored: the window stays as it is.
    }
  }

  /// Shows the window (if it was hidden) and asks the desktop to bring it forward.
  Future<void> present() => _call('present');

  /// With [keep], closing the window hides it and the app keeps running; without, closing it quits.
  Future<void> setKeepRunning(bool keep) => _call('setKeepRunning', keep);
}

/// The XDG autostart entry that starts the app hidden at login, so reminders run without a window. Linux only.
class Autostart {
  Autostart({Map<String, String>? environment, String? executable})
      : _env = environment ?? Platform.environment,
        _exe = executable ?? Platform.resolvedExecutable;
  final Map<String, String> _env;
  final String _exe;

  static const name = 'com.ninepointlabs.bahai_reader-reminders.desktop';

  File get file {
    final xdg = _env['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty ? xdg : '${_env['HOME']}/.config';
    return File('$base/autostart/$name');
  }

  /// The desktop entry's text. The path is quoted as the Desktop Entry spec asks.
  String get entry {
    final quoted = '"${_exe.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}')}"';
    return '[Desktop Entry]\nType=Application\nName=Bahá’í Reader reminders (Flutter experiment)\n'
        'Comment=Keeps reminders running when the Bahá’í Reader window is closed\n'
        'Exec=$quoted --background\nNoDisplay=true\nX-GNOME-Autostart-enabled=true\n';
  }

  /// Writes or removes the entry. Returns null, or a message saying why it could not be changed.
  Future<String?> set(bool wanted) async {
    try {
      if (wanted) {
        await file.parent.create(recursive: true);
        await file.writeAsString(entry);
      } else if (await file.exists()) {
        await file.delete();
      }
      return null;
    } on FileSystemException catch (e) {
      return 'The login entry could not be changed (${e.osError?.message ?? e.message}). Reminders run only while the app is open.';
    }
  }
}
