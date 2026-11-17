import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/cities.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/platform/locator.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';
import 'package:timezone/timezone.dart' as tz;

import 'disk_bundle.dart';
import 'reminders_app_test.dart' show FakeNotifier;

class FakeLocator extends Locator {
  FakeLocator(this.at, [this.problem]);
  final ({double lat, double lon})? at;
  final String? problem;
  @override
  Future<({double lat, double lon})?> locate(void Function(String problem) onProblem) async {
    if (problem != null) onProblem(problem!);
    return at;
  }
}

/// A phone that hasn't allowed reminders at the minute.
class LateNotifier extends FakeNotifier {
  bool asked = false;
  @override
  bool get schedules => true;
  @override
  bool? get exactTimes => false;
  @override
  Future<void> requestExactTimes() async => asked = true;
}

/// "Use my location" and the offer of reminders on time, on phones.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-location'));
  tearDown(() => removeTemp(dir));

  Future<AppState> state() async {
    final s = await AppState.create(
      repository: LibraryRepository(bundle: DiskBundle()),
      store: SettingsStore(File('${dir.path}/settings.json')),
    );
    tz.setLocalLocation(tz.getLocation('America/Chicago'));
    return s;
  }

  test('a point is named after its city, or a nearer town, only when one is close', () async {
    final cities = await (await state()).cities();
    expect(nearestCity(cities, 41.88, -87.63)?.name, 'Chicago');
    expect(nearestCity(cities, 32.82, 34.99)?.name, 'Haifa');
    expect(nearestCity(cities, 42.05, -87.69)?.name, 'Evanston', reason: 'a suburb, more than 5 km from the city');
    expect(nearestCity(cities, 0, -140), isNull, reason: 'the middle of the Pacific');
  });

  test('the device location is rounded, named after the nearest city, and in the device time zone', () async {
    final s = await state();
    s.locator = FakeLocator((lat: 41.87654, lon: -87.62345));
    expect(await s.useDeviceLocation(), isNull);
    final place = s.settings.location!;
    expect((place.lat, place.lon), (41.88, -87.62));
    expect(place.label, startsWith('Near Chicago'));
    expect(place.zone, 'America/Chicago');
    expect(jsonEncode(place.toJson()), isNot(contains('41.876')));

    s.locator = FakeLocator(null, 'Location is turned off in Android’s settings.');
    expect(await s.useDeviceLocation(), 'Location is turned off in Android’s settings.');
    expect(s.settings.location!.label, startsWith('Near Chicago'), reason: 'a failure keeps the saved place');

    s.locator = FakeLocator((lat: 0, lon: -140));
    expect(await s.useDeviceLocation(), isNull);
    expect(s.settings.location!.label, '0.0, -140.0');
  });

  test('reminders may be late only when one is on and the phone has not allowed exact times', () async {
    final s = await state();
    s.notifier = LateNotifier();
    expect(s.remindersMayBeLate, isFalse);
    await s.setReminder('feast', true);
    expect(s.remindersMayBeLate, isTrue);
    expect(s.settings.askedExactTimes, isFalse);
    await s.markAskedExactTimes();
    expect((await SettingsStore(File('${dir.path}/settings.json')).load()).$1.askedExactTimes, isTrue);
  });
}
