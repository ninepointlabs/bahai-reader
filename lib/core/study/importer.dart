/// Importing a PDF into Study: the bytes are hashed, checked to be a PDF and copied into the app's own `books/`
/// folder as `<sha256>.pdf`. The original is only read. Nothing is uploaded anywhere.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

class ImportProblem implements Exception {
  ImportProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedFile {
  const ImportedFile({
    required this.sha256,
    required this.fileName,
    required this.byteSize,
    required this.copy,
    this.pdfDocId,
  });
  final String sha256, fileName;
  final int byteSize;

  /// The app's own copy, which the reader opens.
  final File copy;

  /// The PDF's own document id (its trailer `/ID`), if it has one.
  final String? pdfDocId;
}

String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

/// The first id in a PDF trailer's `/ID [<…> <…>]`, looked for in the file's last 4 KB (and its first 4 KB, for
/// linearized files).
String? pdfDocIdOf(Uint8List bytes) {
  final id = RegExp(r'/ID\s*\[\s*<([0-9A-Fa-f]+)>');
  for (final part in [
    bytes.sublist(bytes.length > 4096 ? bytes.length - 4096 : 0),
    bytes.sublist(0, bytes.length < 4096 ? bytes.length : 4096),
  ]) {
    final m = id.firstMatch(String.fromCharCodes(part));
    if (m != null) return m[1]!.toUpperCase();
  }
  return null;
}

/// Where the app keeps its copy of a book.
File bookFile(Directory books, String sha256) => File('${books.path}/$sha256.pdf');

/// Copies [bytes] (a file called [fileName]) into [books], unless the same file is there already.
Future<ImportedFile> importPdfBytes(Uint8List bytes, String fileName, Directory books) async {
  if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
    throw ImportProblem('“$fileName” is not a PDF file.');
  }
  final hash = await compute(_sha256, bytes);
  final copy = bookFile(books, hash);
  if (!await copy.exists()) {
    await books.create(recursive: true);
    final tmp = File('${copy.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(copy.path);
  }
  return ImportedFile(
    sha256: hash,
    fileName: fileName,
    byteSize: bytes.length,
    copy: copy,
    pdfDocId: pdfDocIdOf(bytes),
  );
}

/// Imports a file from disk (it is only read).
Future<ImportedFile> importPdfFile(File source, Directory books) async {
  final name = source.uri.pathSegments.isEmpty ? 'book.pdf' : source.uri.pathSegments.last;
  final Uint8List bytes;
  try {
    bytes = await source.readAsBytes();
  } on FileSystemException catch (e) {
    throw ImportProblem('“$name” could not be read (${e.osError?.message ?? e.message}).');
  }
  return importPdfBytes(bytes, name, books);
}
