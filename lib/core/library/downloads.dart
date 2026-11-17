/// Downloading a language, or the list of languages, from BahaiPrayers.net: the only network use in the app, and only
/// when the person asks for it in Languages & offline libraries (GTK `download_language()`, `fetch_json()` and the
/// catalog check). The request carries only the collection and the language number. Files are written to this app's
/// own folder, whole or not at all; the GTK app's folder is never written.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'library_repository.dart';
import 'packs.dart';

typedef Fetch = Future<Object?> Function(String endpoint);

const apiBase = 'https://bahaiprayers.net/api/prayer/';

/// GET one BahaiPrayers.net endpoint as JSON, with a 30 second limit, as the GTK app does.
Future<Object?> fetchJson(String endpoint) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse('$apiBase$endpoint')).timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 120));
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}

/// A sentence for people about a failed download (GTK `download_problem()`).
String downloadProblem(Object e) => switch (e) {
  SocketException() ||
  TimeoutException() ||
  HandshakeException() ||
  HttpException() => 'Could not reach bahaiprayers.net. Check your connection and try again.',
  FileSystemException(:final message, :final osError) =>
    'The download could not be saved: ${osError?.message ?? message}.',
  FormatException() || PackError() => 'bahaiprayers.net sent content the app could not use. Try again later.',
  _ => 'The download did not complete. Try again later.',
};

/// Writes [text] to [file] whole or not at all: a temporary file beside it, then a rename.
Future<void> writeAtomically(File file, String text) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.parent.path}/.download-${DateTime.now().microsecondsSinceEpoch}');
  try {
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  } finally {
    if (await tmp.exists()) await tmp.delete();
  }
}

/// Every collection offered in [language], downloaded, checked and saved as one pack in [folders]' own folder. A failure
/// leaves what was there before.
Future<void> downloadLanguage(
  int language,
  Map<String, List<Map<String, dynamic>>> catalog,
  PackFolders folders, {
  Fetch fetch = fetchJson,
  void Function(String)? progress,
}) async {
  final target = folders.ownPack(language);
  if (target == null) throw const FileSystemException('There is nowhere to keep downloads');
  final downloads = <String, Object?>{};
  for (final MapEntry(:key, value: endpoint) in feeds.entries) {
    if (!(catalog[key] ?? const []).any((r) => r['Id'] == language)) continue;
    progress?.call('Downloading ${sectionNames[key]}…');
    final data = await fetch(endpoint.replaceAll('languageid=1', 'languageid=$language'));
    validateFeed(key, data, language);
    downloads[key] = data;
  }
  if (!downloads.containsKey('prayers')) throw PackError('No prayer collection available');
  await writeAtomically(target, jsonEncode(downloads));
}

/// The language list, fetched again and kept in this app's folder (GTK "Check available languages").
Future<Map<String, List<Map<String, dynamic>>>> checkLanguages(PackFolders folders, {Fetch fetch = fetchJson}) async {
  final own = folders.own;
  if (own == null) throw const FileSystemException('There is nowhere to keep the list');
  final fresh = <String, Object?>{};
  for (final MapEntry(:key, value: endpoint) in languageEndpoints.entries) {
    fresh[key] = await fetch(endpoint);
  }
  if (!validCatalog(fresh)) throw const FormatException('Invalid language catalog');
  await writeAtomically(File('${own.path}/languages.json'), jsonEncode(fresh));
  return {
    for (final e in fresh.entries) e.key: [for (final r in e.value as List) (r as Map).cast<String, dynamic>()],
  };
}
