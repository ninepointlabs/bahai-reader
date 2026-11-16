import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

import '../calendar/reminders.dart';

/// What a click on a notification asks for: `said:<mark>` ("Said today") or `open:<target>` (the notification itself,
/// or "Open"; the target is `today` or `prayer:<name>`).
typedef NotificationAction = String;

/// Shows reminders as desktop notifications. Everything stays on this computer: on Linux the notification goes to the
/// desktop's own notification daemon over the local session bus.
abstract class Notifier {
  const Notifier();

  /// Null when notifications can be shown here, else why not (shown in Location & reminders).
  String? get unavailable;

  /// Clicks on notifications, as [NotificationAction]s.
  Stream<NotificationAction> get actions;

  /// Shows [r], replacing what is shown for its group.
  Future<void> send(Reminder r);

  /// Takes down what is shown for [group].
  Future<void> withdraw(String group);

  /// True where reminders are handed to the system ahead of time ([schedule]) because the app is usually not running
  /// when they fall due (Android). Otherwise the app sends each when due, while it runs.
  bool get schedules => false;

  /// Replaces everything handed over before with [later] (only where [schedules]).
  Future<void> schedule(List<Reminder> later) async {}

  /// Clicks made while the app was not listening (Android: "Said today" with the app closed, or a tap that opened it).
  Future<List<NotificationAction>> takePending() async => const [];

  /// Asks for permission to notify, where the system asks (Android 13 and later). Updates [unavailable].
  Future<void> requestPermission() async {}

  static Notifier forPlatform() => Platform.isLinux
      ? LinuxNotifier()
      : Platform.isAndroid
      ? AndroidNotifier()
      : const NoNotifier();
}

/// Where this experiment has no notifications yet (Windows, macOS, Android, iOS).
class NoNotifier extends Notifier {
  const NoNotifier();
  @override
  String? get unavailable => 'Reminders are only sent on Linux and Android in this experiment.';
  @override
  Stream<NotificationAction> get actions => const Stream.empty();
  @override
  Future<void> send(Reminder r) async {}
  @override
  Future<void> withdraw(String group) async {}
}

/// The freedesktop notification spec (`org.freedesktop.Notifications`), which mako, dunst, GNOME and KDE all serve.
class LinuxNotifier extends Notifier {
  LinuxNotifier({this.appName = 'Bahá’í Reader', this.desktopEntry = 'com.ninepointlabs.bahai_reader'});
  final String appName, desktopEntry;

  static const _iface = 'org.freedesktop.Notifications';
  DBusRemoteObject? _object;
  final _actions = StreamController<NotificationAction>.broadcast();
  final Map<String, int> _shown = {}; // group → notification id
  final Map<int, Reminder> _byId = {};
  String? _problem;

  @override
  String? get unavailable => _problem;

  @override
  Stream<NotificationAction> get actions => _actions.stream;

  DBusRemoteObject _connect() {
    if (_object != null) return _object!;
    final client = DBusClient.session();
    final object = _object = DBusRemoteObject(
      client,
      name: _iface,
      path: DBusObjectPath('/org/freedesktop/Notifications'),
    );
    DBusSignalStream(
      client,
      interface: _iface,
      name: 'ActionInvoked',
      path: object.path,
      signature: DBusSignature('us'),
    ).listen((s) {
      final r = _byId[s.values[0].asUint32()];
      if (r == null) return;
      final key = s.values[1].asString();
      if (key == 'said' && r.said != null) {
        _actions.add('said:${r.said}');
      } else {
        _actions.add('open:${r.opens}');
      }
    }, onError: (_) {});
    DBusSignalStream(
      client,
      interface: _iface,
      name: 'NotificationClosed',
      path: object.path,
      signature: DBusSignature('uu'),
    ).listen((s) {
      // The group's next reminder starts afresh; the reminder itself is kept, as a server with a history (quickshell,
      // GNOME, KDE) still sends a click on it after its popup has gone.
      final id = s.values[0].asUint32();
      _shown.removeWhere((_, v) => v == id);
    }, onError: (_) {});
    return object;
  }

  @override
  Future<void> send(Reminder r) async {
    try {
      final result = await _connect().callMethod(_iface, 'Notify', [
        DBusString(appName),
        DBusUint32(_shown[r.group] ?? 0),
        const DBusString('x-office-calendar'),
        DBusString(r.title),
        // Servers that offer body markup read the body as markup, so its text is escaped.
        DBusString(r.body.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')),
        DBusArray.string([
          'default',
          'Open',
          if (r.said != null) ...['said', 'Said today'],
          'open',
          'Open',
        ]),
        DBusDict.stringVariant({
          'desktop-entry': DBusString(desktopEntry),
          'category': const DBusString('x-bahai-reader.reminder'),
        }),
        const DBusInt32(-1),
      ], replySignature: DBusSignature('u'));
      final id = result.values[0].asUint32();
      _shown[r.group] = id;
      _byId[id] = r;
      while (_byId.length > 64) {
        _byId.remove(_byId.keys.first);
      }
      _problem = null;
    } catch (e) {
      _problem = 'Notifications could not be shown: no notification service answered on this desktop.';
    }
  }

  @override
  Future<void> withdraw(String group) async {
    final id = _shown.remove(group);
    if (id == null) return;
    try {
      await _connect().callMethod(_iface, 'CloseNotification', [DBusUint32(id)], replySignature: DBusSignature(''));
    } catch (_) {}
  }
}

/// Android (android/app/src/main/kotlin/.../Reminders.kt): reminders are set as alarms a week ahead and shown by the
/// system's notifications, with or without the app running; alarms are set again after a restart of the phone. Nothing
/// leaves the device.
class AndroidNotifier extends Notifier {
  AndroidNotifier() {
    _channel.setMethodCallHandler((call) async {
      // Something was queued while the app runs (a tap on Open, or Said today): fetch it.
      if (call.method == 'pending') _actions.add('pending');
    });
  }
  static const _channel = MethodChannel('bahai_reader/reminders');
  final _actions = StreamController<NotificationAction>.broadcast();
  bool _enabled = true;

  @override
  String? get unavailable => _enabled ? null : 'Notifications are turned off for this app in Android’s settings.';

  @override
  Stream<NotificationAction> get actions => _actions.stream;

  @override
  bool get schedules => true;

  static Map<String, Object?> _map(Reminder r) => {
    'key': r.id,
    'tag': r.group,
    'title': r.title,
    'body': r.body,
    'at': r.at.millisecondsSinceEpoch,
    'until': r.until.millisecondsSinceEpoch,
    'said': r.said,
    'opens': r.opens,
  };

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> send(Reminder r) async {
    _enabled = await _call<bool>('show', _map(r)) ?? _enabled;
  }

  @override
  Future<void> withdraw(String group) => _call<void>('withdraw', group);

  @override
  Future<void> schedule(List<Reminder> later) async {
    _enabled = await _call<bool>('schedule', [for (final r in later) _map(r)]) ?? _enabled;
  }

  @override
  Future<List<NotificationAction>> takePending() async =>
      (await _call<List<Object?>>('takePending'))?.whereType<String>().toList() ?? const [];

  @override
  Future<void> requestPermission() async {
    _enabled = await _call<bool>('requestPermission') ?? _enabled;
  }

  /// The device's time zone (Android has no `/etc/localtime` for Dart to read).
  static Future<String?> deviceZone() async {
    try {
      return await _channel.invokeMethod<String>('zone');
    } catch (_) {
      return null;
    }
  }
}
