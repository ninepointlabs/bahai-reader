import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/study/study_controller.dart';
import 'study_actions.dart';

const _files = MethodChannel('bahai_reader/files');

/// Android: PDFs opened with Bahá’í Reader from a file manager or shared to it (MainActivity reads them once, see
/// StudyFiles.kt) are imported into Study and opened. [opened] shows the book.
void listenForIncomingPdfs(BuildContext Function() context, StudyController? study, VoidCallback opened) {
  if (!Platform.isAndroid || study == null) return;
  Future<void> take() async {
    final List<Object?> items;
    try {
      items = await _files.invokeMethod<List<Object?>>('takeIncoming') ?? const [];
    } on PlatformException {
      return;
    }
    for (final item in items) {
      if (item is! Map) continue;
      final c = context();
      if (!c.mounted) return;
      final name = item['name'] as String? ?? 'book.pdf';
      final bytes = item['bytes'];
      if (bytes is Uint8List) {
        await importStudyBytes(c, study, bytes, name, opened: opened);
      } else {
        ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(content: Text('“$name” could not be read (${item['error'] ?? 'unknown problem'}).')),
        );
      }
    }
  }

  _files.setMethodCallHandler((call) async {
    if (call.method == 'incoming') await take();
  });
  WidgetsBinding.instance.addPostFrameCallback((_) => take());
}
