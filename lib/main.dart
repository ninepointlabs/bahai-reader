import 'package:flutter/material.dart';

import 'core/app/app_state.dart';
import 'core/app/theme.dart';
import 'features/library/library_screen.dart';

/// `--open <passage id>` opens that passage at startup (e.g. `--open hidden:2`).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  final at = args.indexOf('--open');
  runApp(BahaiReaderApp(state: state, openId: at >= 0 && at + 1 < args.length ? args[at + 1] : null));
}

class BahaiReaderApp extends StatelessWidget {
  const BahaiReaderApp({super.key, required this.state, this.openId});
  final AppState state;
  final String? openId;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Bahá’í Reader (Flutter experiment)',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          home: LibraryScreen(openId: openId),
        ),
      ),
    );
  }
}
