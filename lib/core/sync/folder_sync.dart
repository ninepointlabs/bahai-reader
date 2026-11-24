/// Syncing through a folder that another program keeps in step between devices (Syncthing, Dropbox, Nextcloud,
/// OneDrive, iCloud Drive…). Nothing goes over the network from this app.
///
/// Each device writes one file of its own, `bahai-reader-notes-<device id>.json` (its notes export, see
/// [UserDataStore.exportAll]), and reads the other devices' files, merging them record by record (the version changed
/// last wins). As no two devices write the same file, the syncing program never has two versions of one file to
/// reconcile; its conflict copies, if any, are merged like any other file. With books shared, imported PDFs are copied
/// into `bahai-reader-books/` and taken from there by devices that don't have them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../userdata/userdata_store.dart';

/// A file in the sync folder.
class SyncEntry {
  const SyncEntry(this.name, this.modified, this.size);
  final String name;
  final int modified, size;

  /// What changes when the file does (for "read it again?").
  String get signature => '$modified:$size';
}

/// The folder synced by another program: a directory on disk, or (Android) a folder chosen in the system picker.
abstract class SyncFolder {
  /// The files in it, or in its subfolder [sub].
  Future<List<SyncEntry>> list([String? sub]);
  Future<Uint8List?> read(String name, [String? sub]);
  Future<void> write(String name, Uint8List bytes, [String? sub]);
}

/// A folder on disk (Linux, Windows, macOS).
class DirectoryFolder implements SyncFolder {
  DirectoryFolder(this.dir);
  final Directory dir;

  Directory _in(String? sub) => sub == null ? dir : Directory('${dir.path}/$sub');

  @override
  Future<List<SyncEntry>> list([String? sub]) async {
    final d = _in(sub);
    if (!await d.exists()) return const [];
    return [
      for (final f in d.listSync().whereType<File>())
        if (f.statSync() case final st) SyncEntry(f.uri.pathSegments.last, st.modified.millisecondsSinceEpoch, st.size),
    ];
  }

  @override
  Future<Uint8List?> read(String name, [String? sub]) async {
    final f = File('${_in(sub).path}/$name');
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Written to a hidden temporary file first, then renamed, so the syncing program never sends half a file.
  @override
  Future<void> write(String name, Uint8List bytes, [String? sub]) async {
    final d = _in(sub);
    await d.create(recursive: true);
    final tmp = File('${d.path}/.$name.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${d.path}/$name');
  }
}

const notesPrefix = 'bahai-reader-notes-';
const booksFolder = 'bahai-reader-books';

class SyncResult {
  int merged = 0, changed = 0, devices = 0, booksIn = 0, booksOut = 0;
  bool wrote = false;
  final List<String> problems = [];
}

class FolderSync {
  FolderSync({required this.folder, required this.data, required this.onMerged, this.books, this.shareBooks = false});
  final SyncFolder folder;
  final UserDataStore data;

  /// After another device's changes came in (the app reloads its marks).
  final Future<void> Function() onMerged;

  /// This device's imported PDFs (`<sha256>.pdf`), shared when [shareBooks].
  final Directory? books;
  final bool shareBooks;

  String get ownName => '$notesPrefix${data.deviceId}.json';

  /// Reads the other devices' files that changed since last time and merges them, then writes this device's file if
  /// anything changed here (or it is missing), then shares books.
  Future<SyncResult> sync() async {
    final r = SyncResult();
    final files = await folder.list();
    var changedHere = false;
    for (final f in files) {
      if (!f.name.startsWith(notesPrefix) || !f.name.endsWith('.json') || f.name == ownName) continue;
      r.devices++;
      final key = 'sync.seen.${f.name}';
      if (data.meta(key) == f.signature) continue;
      try {
        final bytes = await folder.read(f.name);
        if (bytes == null) continue;
        final bundle = jsonDecode(utf8.decode(bytes));
        if (bundle is! Map) throw const FormatException('not an object');
        final m = data.merge(bundle.cast<String, Object?>());
        r.merged++;
        if (m.changed > 0) {
          r.changed += m.changed;
          changedHere = true;
        }
        data.setMeta(key, f.signature);
      } on FormatException {
        r.problems.add('${f.name} could not be read (perhaps still arriving); it will be tried again.');
      } on UserDataProblem catch (e) {
        r.problems.add('${f.name} was not merged: $e.');
        data.setMeta(key, f.signature);
      }
    }
    if (changedHere) await onMerged();
    final own = files.where((f) => f.name == ownName).firstOrNull;
    if (own == null || data.meta('sync.wrote') != data.stamp) {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data.exportAll())));
      await folder.write(ownName, bytes);
      data.setMeta('sync.wrote', data.stamp);
      r.wrote = true;
    }
    if (shareBooks && books != null) await _books(r);
    data.setMeta('sync.at', DateTime.now().toUtc().toIso8601String());
    return r;
  }

  /// Copies this device's imported PDFs into the folder, and takes in those it is missing.
  Future<void> _books(SyncResult r) async {
    final dir = books!;
    final there = {for (final f in await folder.list(booksFolder)) f.name};
    final wanted = {
      for (final d in data.records('doc_file'))
        if (d['sha256'] is String) '${d['sha256']}.pdf',
    };
    for (final name in wanted) {
      final local = File('${dir.path}/$name');
      final have = await local.exists();
      if (have && !there.contains(name)) {
        await folder.write(name, await local.readAsBytes(), booksFolder);
        r.booksOut++;
      } else if (!have && there.contains(name)) {
        final bytes = await folder.read(name, booksFolder);
        // Only the very file: a copy still arriving (or damaged) is left for next time.
        if (bytes == null || '${sha256.convert(bytes)}.pdf' != name) continue;
        await dir.create(recursive: true);
        final tmp = File('${local.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(local.path);
        r.booksIn++;
      }
    }
  }
}
