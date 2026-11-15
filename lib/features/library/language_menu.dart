import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';

/// Switches among the languages bundled offline.
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<int>(
      tooltip: 'Language',
      initialValue: state.settings.language,
      onSelected: state.setLanguage,
      itemBuilder: (_) => [
        for (final l in state.languages) PopupMenuItem(value: l.id, child: Text(l.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.translate, size: 20),
          const SizedBox(width: 6),
          Text(state.language.name),
        ]),
      ),
    );
  }
}
