import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';

import 'core/app/about.dart';
import 'core/app/app_state.dart';
import 'core/library/library_repository.dart';
import 'core/app/theme.dart';
import 'core/calendar/zones.dart';
import 'core/platform/locator.dart';
import 'core/platform/notifier.dart';
import 'core/platform/window_control.dart';
import 'features/desktop/shell.dart';
import 'features/library/library_screen.dart';

/// `--open <passage id>` opens that passage at startup (e.g. `--open hidden:2`).
/// `--background` (the login entry, Linux) starts with the window hidden, only to send reminders.
Future<void> main(List<String> args) async {
  final known = {'--background', '--open'};
  if (args.length == 1 && (args.first == '-h' || args.first == '--help')) {
    stdout.writeln(usage());
    exit(0);
  }
  if (args.length == 1 && args.first == '--version') {
    stdout.writeln('$appName $appVersion');
    exit(0);
  }
  for (var i = 0; i < args.length; i++) {
    if (!known.contains(args[i])) {
      stderr.writeln('bahai-reader: unknown option ${args[i]}. Try bahai-reader --help.');
      exit(2);
    }
    if (args[i] == '--open') i++;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final folders = PackFolders.standard(appSupport: Platform.isLinux ? null : await getApplicationSupportDirectory());
  final state = await AppState.create(repository: LibraryRepository(folders: folders));
  // A login entry left behind after "Keep reminders running" was turned off elsewhere: nothing to do.
  if (args.contains('--background') && !state.settings.keepRunning) exit(0);
  if (Platform.isLinux) {
    state.watchOmarchyTheme();
    state.startReminders(Notifier.forPlatform(), autostart: Autostart());
  }
  if (Platform.isAndroid) {
    final zone = await AndroidNotifier.deviceZone();
    if (zone != null) useZone(zone);
    state.locator = const AndroidLocator();
    state.startReminders(Notifier.forPlatform());
  }
  final at = args.indexOf('--open');
  runApp(BahaiReaderApp(state: state, openId: at >= 0 && at + 1 < args.length ? args[at + 1] : null));
}

/// Desktops get the GTK app's window layout (sidebar, header bar, reading pane); phones and tablets the touch layout.
bool get isDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
      _ => false,
    };

class BahaiReaderApp extends StatelessWidget {
  const BahaiReaderApp({super.key, required this.state, this.openId, this.desktop});
  final AppState state;
  final String? openId;

  /// Forces the desktop (true) or touch (false) layout; by default it follows the platform.
  final bool? desktop;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final fixed = state.fixedPalette;
          return MaterialApp(
            title: 'Bahá’í Reader (Flutter experiment)',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(fixed ?? Palette.light, monospace: state.settings.chromeFont == 'Monospace'),
            darkTheme: buildTheme(fixed ?? Palette.dark, monospace: state.settings.chromeFont == 'Monospace'),
            themeMode: state.themeMode,
            home: (desktop ?? isDesktop) ? DesktopShell(state: state, openId: openId) : LibraryScreen(openId: openId),
          );
        },
      ),
    );
  }
}
