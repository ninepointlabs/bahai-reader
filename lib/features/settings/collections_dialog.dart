import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/settings/settings_store.dart';

/// Collections: create, rename and delete the named groups of saved passages (GTK `collections_dialog()`). Deleting a
/// collection keeps its passages saved, under Unsorted.
class CollectionsDialog extends StatefulWidget {
  const CollectionsDialog({super.key});

  @override
  State<CollectionsDialog> createState() => _CollectionsDialogState();
}

class _CollectionsDialogState extends State<CollectionsDialog> {
  final create = TextEditingController();
  final Map<String, TextEditingController> names = {};
  String message = '';

  @override
  void dispose() {
    create.dispose();
    for (final c in names.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create(AppState state) async {
    final problem = await state.createCollection(create.text);
    setState(() => message = problem ?? '');
    if (problem == null) create.clear();
  }

  Future<void> _rename(AppState state, String old) async {
    final problem = await state.renameCollection(old, names[old]!.text);
    if (problem == null) {
      final controller = names.remove(old)!;
      names[collectionName(controller.text)] = controller..text = collectionName(controller.text);
    }
    setState(() => message = problem ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final collections = state.settings.collections;
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Group saved passages into collections. Deleting a collection keeps its passages saved, under $unsorted.'),
        const SizedBox(height: 16),
        if (collections.isEmpty) const Text('No collections yet.'),
        for (final c in collections)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: names.putIfAbsent(c.name, () => TextEditingController(text: c.name)),
                  decoration: InputDecoration(isDense: true, labelText: 'Collection “${c.name}”'),
                  onSubmitted: (_) => _rename(state, c.name),
                ),
              ),
              const SizedBox(width: 8),
              Text('${c.items.length} passage${c.items.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _rename(state, c.name), child: const Text('Rename')),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () async {
                  final name = c.name;
                  await state.deleteCollection(name);
                  names.remove(name)?.dispose();
                  setState(() => message = 'Deleted “$name”; its passages are under $unsorted.');
                },
                child: const Text('Delete'),
              ),
            ]),
          ),
        if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(message)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: create,
              autofocus: true,
              decoration: const InputDecoration(isDense: true, hintText: 'New collection name'),
              onSubmitted: (_) => _create(state),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _create(state), child: const Text('Create')),
        ]),
      ]),
    );
  }
}

Future<void> showCollections(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600), child: const CollectionsDialog()),
      ),
    );

/// Under a saved passage: which collection it is in, and Manage… (GTK `show_filing()`).
class FilingRow extends StatelessWidget {
  const FilingRow({super.key, required this.savedKey});
  final String savedKey;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final current = state.collectionOf(savedKey) ?? '';
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        const Text('Collection'),
        DropdownMenu<String>(
          key: ValueKey('filing-$savedKey-$current-${state.settings.collections.length}'),
          initialSelection: current,
          width: 220,
          textStyle: const TextStyle(fontSize: 14),
          onSelected: (name) => name == null ? null : state.moveSaved(savedKey, name.isEmpty ? null : name),
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: unsorted),
            for (final c in state.settings.collections) DropdownMenuEntry(value: c.name, label: c.name),
          ],
        ),
        TextButton(onPressed: () => showCollections(context), child: const Text('Manage…')),
      ],
    );
  }
}
