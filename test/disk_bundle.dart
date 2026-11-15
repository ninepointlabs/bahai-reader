import 'dart:io';

import 'package:flutter/services.dart';

/// Serves assets straight from the repository, so tests use the real converted library.
class DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(await File(key).readAsBytes()));

  @override
  Future<String> loadString(String key, {bool cache = true}) => File(key).readAsString();
}
