/// Android: whether notes, highlights, answers and settings may be copied to the person's Android backup (their
/// Google account) and to a new phone. Imported Study books never are (`res/xml/*_rules.xml` exclude `books/`).
///
/// Android's backup rules are fixed when the app is built, so the choice moves the files instead: they live in the app's
/// `files/` folder (backed up, as Android does by default), or in `files/nobackup/`, which the rules exclude. The
/// choice is kept in `files/backup-choice` and takes effect at the next start, before anything is opened.
library;

import 'dart:io';

const _choiceFile = 'backup-choice';
const noBackupFolder = 'nobackup';

/// The files that move with the choice: the settings, the user-data store, and their backups and set-aside copies.
bool _moves(String name) =>
    name == 'settings.json' ||
    name.startsWith('settings.json.') ||
    name == 'userdata.sqlite' ||
    name.startsWith('userdata.sqlite-');

/// True when notes may go into Android's backup (the default), false when they are kept out of it.
bool notesInBackup(Directory files) {
  final f = File('${files.path}/$_choiceFile');
  try {
    return !f.existsSync() || f.readAsStringSync().trim() != 'exclude';
  } on FileSystemException {
    return true;
  }
}

/// Records the choice; the files move at the next start.
Future<void> chooseNotesInBackup(Directory files, bool include) async {
  await files.create(recursive: true);
  await File('${files.path}/$_choiceFile').writeAsString(include ? 'include' : 'exclude', flush: true);
}

/// The folder the settings and notes are in, after moving them to match the choice if needed. A folder that already
/// has a settings file is never overwritten: if both have one, the files stay where they are and that folder is used.
Future<Directory> userDataFolder(Directory files) async {
  final private = Directory('${files.path}/$noBackupFolder');
  final include = notesInBackup(files);
  final (from, to) = include ? (private, files) : (files, private);
  final fromSettings = File('${from.path}/settings.json');
  final toSettings = File('${to.path}/settings.json');
  if (!await fromSettings.exists()) {
    await to.create(recursive: true);
    return to;
  }
  if (await toSettings.exists()) return from;
  await to.create(recursive: true);
  for (final e in from.listSync().whereType<File>()) {
    final name = e.uri.pathSegments.last;
    if (_moves(name)) await e.rename('${to.path}/$name');
  }
  return to;
}
