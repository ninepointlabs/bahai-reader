/// Identifiers and clocks for records that may one day be synced between devices.
///
/// * [uuidV7]: a new random id that sorts by creation time (RFC 9562), for records with no natural key (a highlight).
/// * [uuidV5]: the same id on every device for the same meaning (`saved:hidden:2`), so two devices that make the "same"
///   record converge on one instead of duplicating it.
/// * [Hlc]: a hybrid logical clock. Its stamps order changes correctly even when two devices' clocks disagree, and
///   compare as plain strings.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _random = Random.secure();

String _format(List<int> b) {
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A UUIDv7: 48 bits of Unix milliseconds, then random bits.
String uuidV7([DateTime? at]) {
  final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  for (var i = 0; i < 6; i++) {
    b[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  b[6] = 0x70 | (b[6] & 0x0f);
  b[8] = 0x80 | (b[8] & 0x3f);
  return _format(b);
}

/// This app's namespace for [uuidV5] ids. Never change it: stored ids depend on it.
const userDataNamespace = '6f1d6a2e-3b7c-4e0a-9c55-0b7e2f4d8a13';

List<int> _uuidBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return [for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

final _v5 = <String, String>{};

/// A UUIDv5 (SHA-1 of [namespace] and [name]): the same input always gives the same id.
String uuidV5(String name, [String namespace = userDataNamespace]) {
  if (namespace == userDataNamespace) {
    if (_v5.length > 50000) _v5.clear();
    return _v5[name] ??= _uuidV5(name, namespace);
  }
  return _uuidV5(name, namespace);
}

String _uuidV5(String name, String namespace) {
  final digest = sha1.convert([..._uuidBytes(namespace), ...utf8.encode(name)]).bytes.sublist(0, 16);
  digest[6] = 0x50 | (digest[6] & 0x0f);
  digest[8] = 0x80 | (digest[8] & 0x3f);
  return _format(digest);
}

/// A hybrid logical clock: wall milliseconds, a counter for changes within one millisecond (or while the wall clock is
/// behind the last stamp), and the device id to break ties. Stamps look like `00lzx3k9c-0000-<device>` and sort as
/// strings in the order the changes were made.
class Hlc {
  Hlc(this.device, {this.wall = 0, this.counter = 0});

  final String device;
  int wall;
  int counter;

  /// A stamp for a change made now, later than every stamp this clock has given or seen.
  String next([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now > wall) {
      wall = now;
      counter = 0;
    } else {
      counter++;
    }
    return stamp;
  }

  String get stamp => '${wall.toRadixString(36).padLeft(9, '0')}-${counter.toRadixString(36).padLeft(4, '0')}-$device';

  /// Takes in a stamp from another device so later local stamps sort after it.
  void observe(String other) {
    final parsed = parse(other);
    if (parsed == null) return;
    final (w, c) = parsed;
    if (w > wall || (w == wall && c > counter)) {
      wall = w;
      counter = c;
    }
  }

  static (int, int)? parse(String s) {
    final parts = s.split('-');
    if (parts.length < 3) return null;
    final w = int.tryParse(parts[0], radix: 36), c = int.tryParse(parts[1], radix: 36);
    return w == null || c == null ? null : (w, c);
  }
}
