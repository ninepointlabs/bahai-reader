import 'dart:io';

/// Removes a test's temporary folder. Windows refuses to delete a file that is still open, and a widget test can end
/// with the app's last write still pending, so there a folder that cannot be removed is left to the system's temp cleanup.
void removeTemp(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
}
