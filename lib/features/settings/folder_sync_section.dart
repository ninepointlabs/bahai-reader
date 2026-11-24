import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/sync/android_tree_folder.dart';

/// Settings → Sync through a folder: pick a folder that Syncthing, Dropbox, Nextcloud, OneDrive or iCloud Drive keeps
/// in step between your devices; each device keeps its notes there and takes in the others'. The app itself never uses
/// the network.
class FolderSyncSection extends StatelessWidget {
  const FolderSyncSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final folder = state.settings.syncFolder;
    final dim = theme.textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sync through a folder', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Choose a folder that a sync program (Syncthing, Dropbox, Nextcloud, OneDrive, iCloud Drive…) keeps the same '
          'on your computer and phone, and choose the same folder on each. Each device keeps its notes there in a file of '
          'its own and takes in the others’ changes; when the same note was changed on two devices, the later change '
          'is kept. Bahá’í Reader itself never goes online: the sync program carries the files.',
          style: dim,
        ),
        const SizedBox(height: 8),
        if (folder == null)
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_shared_outlined, size: 18),
            label: const Text('Choose a sync folder…'),
            onPressed: state.userData == null ? null : () => _choose(context, state),
          )
        else ...[
          FutureBuilder<String?>(
            future: folder.startsWith('content://') ? androidFolderName(folder) : Future.value(folder),
            builder: (context, snap) => SelectableText('Folder: ${snap.data ?? folder}'),
          ),
          const SizedBox(height: 4),
          Text(_status(state), style: dim),
          if (state.syncProblem != null) Text(state.syncProblem!, style: dim?.copyWith(color: theme.colorScheme.error)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Share imported Study PDFs too'),
            subtitle: const Text(
              'Your imported PDFs are copied into the folder (in bahai-reader-books), so a book imported on one device '
              'opens on the others. They are your own copies; keep the folder private. Turn this off to import each '
              'book on each device yourself.',
            ),
            value: state.settings.syncBooks,
            onChanged: (v) => state.setSyncFolder(folder, books: v ?? false),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sync now'),
                onPressed: state.syncNow,
              ),
              TextButton(onPressed: () => _choose(context, state), child: const Text('Choose another folder…')),
              TextButton(onPressed: () => state.setSyncFolder(null), child: const Text('Stop syncing')),
            ],
          ),
        ],
      ],
    );
  }

  static String _status(AppState state) {
    final at = state.lastSyncAt, r = state.lastSync;
    if (at == null || r == null) return 'Not synced yet.';
    final ago = DateTime.now().difference(at);
    final when = ago.inMinutes < 1 ? 'just now' : '${ago.inMinutes} min ago';
    final others = r.devices == 0
        ? 'no other device has written to it yet'
        : '${r.devices} other device${r.devices == 1 ? '' : 's'}';
    return 'Last synced $when · $others${r.changed > 0 ? ' · ${r.changed} changes taken in' : ''}.';
  }

  Future<void> _choose(BuildContext context, AppState state) async {
    final String? path = Platform.isAndroid
        ? await pickAndroidFolder()
        : await getDirectoryPath(confirmButtonText: 'Sync here');
    if (path != null) await state.setSyncFolder(path);
  }
}
