/// What the app is called, who made it and how to reach them (GTK `config.py`), and the `--help` text.
library;

import 'dart:io';

const appName = 'Bahá’í Reader';
const tagline = 'A quiet, native reader for Bahá’í prayers and writings.';
const organization = 'Nine Point Labs';
const supportEmail = 'help@ninepointlabs.com';
const created = 'September 13, 2026';
const licenseName = 'MIT License';
const copyright = '© 2026 Nine Point Labs';

/// The app's version; keep it equal to `version:` in pubspec.yaml (test/about_test.dart checks).
const appVersion = '1.0.1';

String _short(String path) {
  final home = Platform.environment['HOME'];
  return home != null && path.startsWith(home) ? '~${path.substring(home.length)}' : path;
}

/// `bahai-reader --help` (GTK `usage()`).
String usage() {
  String base(String name, String fallback) {
    final xdg = Platform.environment[name];
    return xdg != null && xdg.isNotEmpty ? xdg : '${Platform.environment['HOME']}/$fallback';
  }

  final data = base('XDG_DATA_HOME', '.local/share'), config = base('XDG_CONFIG_HOME', '.config');
  return 'Usage: bahai-reader [--help | --version | --background | --open PASSAGE]\n\n$tagline\n'
      'With no options it opens the reader window; a second launch shows the open window.\n\n'
      'Options:\n  -h, --help        Show this help and exit\n  --version         Show the version and exit\n'
      '  --background      Run reminders with no window; a later launch opens the window in the same process\n'
      '  --open PASSAGE    Open a passage by its id, such as hidden:2\n\n'
      'Settings and saved passages: ${_short('$config/bahai-reader-flutter/settings.json')}\n'
      'Downloaded languages: ${_short('$data/bahai-reader-flutter/libraries')}\n'
      'Support: $supportEmail';
}
