import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/citations.dart';
import '../../core/library/passage.dart';
import '../../core/marks/highlight.dart';

/// Asks for a note. Returns the text (possibly empty, meaning "no note"), or null if cancelled.
Future<String?> editNote(BuildContext context, String? initial) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          maxLength: noteLimit,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Your note (kept on this device only)'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
}

/// Change a highlight's colour, write or edit its note, copy its words with the citation, or remove it.
Future<void> showHighlightSheet(BuildContext context, Highlight record, Passage passage) {
  final state = AppScope.read(context);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('“${excerpt(record.words, 200)}”', style: Theme.of(sheet).textTheme.bodyMedium),
          if (record.note != null) ...[
            const SizedBox(height: 8),
            Text(record.note!, maxLines: 6, overflow: TextOverflow.ellipsis, style: Theme.of(sheet).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Row(children: [
            for (final c in highlightColors)
              IconButton(
                tooltip: c,
                isSelected: c == record.color,
                icon: Icon(c == record.color ? Icons.check_circle : Icons.circle, color: swatchColor(c)),
                onPressed: () {
                  Navigator.pop(sheet);
                  state.updateHighlight(record, color: c);
                },
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Copy with citation',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: clipping(passage, record.words)));
                Navigator.pop(sheet);
              },
            ),
            IconButton(
              tooltip: record.note == null ? 'Add note' : 'Edit note',
              icon: const Icon(Icons.sticky_note_2_outlined),
              onPressed: () async {
                Navigator.pop(sheet);
                final note = await editNote(context, record.note);
                if (note != null) await state.updateHighlight(record, note: note);
              },
            ),
            IconButton(
              tooltip: 'Remove highlight',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Navigator.pop(sheet);
                state.removeHighlight(record);
              },
            ),
          ]),
        ]),
      ),
    ),
  );
}
