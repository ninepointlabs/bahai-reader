import 'dart:io';

import 'package:bahai_reader/core/userdata/userdata_store.dart';

/// What the user-data store beside [settingsFile] holds, in `settings.json`'s shapes (without the store's own ids),
/// read through a connection of its own, as the next start would read it.
Map<String, Object> storedMarks(File settingsFile) {
  final store = UserDataStore.open(settingsFile);
  try {
    final data = store.toJson();
    for (final key in ['highlights', 'collections']) {
      for (final r in data[key] as List) {
        (r as Map).remove('uid');
      }
    }
    return data;
  } finally {
    store.close();
  }
}
