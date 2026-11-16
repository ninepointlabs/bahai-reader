import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _ready = false;

/// Loads the bundled time-zone database (no network) and sets this computer's zone: the `TZ` variable, else the
/// `/etc/localtime` link (Linux, macOS), else a zone with the same current offset, else UTC.
void initTimeZones() {
  if (_ready) return;
  _ready = true;
  tzdata.initializeTimeZones();
  tz.setLocalLocation(localZone());
}

tz.Location localZone() {
  String? name = Platform.environment['TZ'];
  if (name != null && name.startsWith(':')) name = name.substring(1);
  if (name == null || name.isEmpty) {
    try {
      final link = Link('/etc/localtime').targetSync();
      final at = link.indexOf('zoneinfo/');
      if (at >= 0) name = link.substring(at + 'zoneinfo/'.length);
    } on FileSystemException {
      name = null;
    }
  }
  if (name != null) {
    try {
      return tz.getLocation(name);
    } catch (_) {}
  }
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  for (final l in tz.timeZoneDatabase.locations.values) {
    if (l.currentTimeZone.offset == offset && l.currentTimeZone.abbreviation == now.timeZoneName) return l;
  }
  return tz.UTC;
}
