import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/app/app_state.dart';
import 'core/app/theme.dart';
import 'core/platform/notifier.dart';
import 'core/platform/window_control.dart';
import 'features/desktop/shell.dart';
import 'features/library/library_screen.dart';

/// `--open <passage id>` opens that passage at startup (e.g. `--open hidden:2`).
/// `--background` (the login entry, Linux) starts with the window hidden, only to send reminders.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  // A login entry left behind after "Keep reminders running" was turned off elsewhere: nothing to do.
  if (args.contains('--background') && !state.settings.keepRunning) exit(0);
  if (Platform.isLinux) {
    state.watchOmarchyTheme();
    state.startReminders(Notifier.forPlatform(), autostart: Autostart());
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
            theme: buildTheme(fixed ?? Palette.light),
            darkTheme: buildTheme(fixed ?? Palette.dark),
            themeMode: state.themeMode,
            home: (desktop ?? isDesktop) ? DesktopShell(state: state, openId: openId) : LibraryScreen(openId: openId),
          );
        },
      ),
    );
  }
}
