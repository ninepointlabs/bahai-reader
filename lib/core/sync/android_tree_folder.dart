/// Android: a sync folder chosen in the system's folder picker (a `content://` tree the app was given lasting access
/// to), used through the `bahai_reader/folder` channel (SyncTree.kt). No storage permission is needed.
library;

import 'package:flutter/services.dart';

import 'folder_sync.dart';

const _channel = MethodChannel('bahai_reader/folder');

/// Opens the system folder picker; the chosen folder's address, or null.
Future<String?> pickAndroidFolder() => _channel.invokeMethod<String>('pick');

/// A readable name for a chosen folder ("Syncthing/Notes").
Future<String?> androidFolderName(String uri) => _channel.invokeMethod<String>('name', {'uri': uri});

class AndroidTreeFolder implements SyncFolder {
  AndroidTreeFolder(this.uri);
  final String uri;

  @override
  Future<List<SyncEntry>> list([String? sub]) async {
    final rows = await _channel.invokeMethod<List<Object?>>('list', {'uri': uri, 'sub': sub}) ?? const [];
    return [
      for (final r in rows)
        if (r is Map)
          SyncEntry(r['name'] as String, (r['modified'] as num?)?.toInt() ?? 0, (r['size'] as num?)?.toInt() ?? 0),
    ];
  }

  @override
  Future<Uint8List?> read(String name, [String? sub]) =>
      _channel.invokeMethod<Uint8List>('read', {'uri': uri, 'name': name, 'sub': sub});

  @override
  Future<void> write(String name, Uint8List bytes, [String? sub]) =>
      _channel.invokeMethod<void>('write', {'uri': uri, 'name': name, 'sub': sub, 'bytes': bytes});
}
