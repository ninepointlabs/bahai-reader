import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/badi.dart';
import '../../core/calendar/cities.dart';
import '../../core/calendar/reminders.dart';
import '../desktop/widgets.dart';
import 'exact_times.dart';

/// Location & reminders (GTK `location.py`): where the sun times are worked out for, clock hours in place of the sun,
/// which obligatory prayer is said and its reminders, the Long prayer's twenty-four hours, the private record of Said
/// and Fasted, reminders of Feasts, Holy Days and the Fast, and keeping reminders running with the window closed.
Future<void> showLocationDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
      child: const LocationPage(),
    ),
  ),
);

/// The same settings as a full page, for the phone layout.
Future<void> showLocationPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LocationPage(page: true)));

class LocationPage extends StatefulWidget {
  const LocationPage({super.key, this.page = false});

  /// A full page with an app bar (phones), rather than the desktop dialog with its header bar.
  final bool page;

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final search = TextEditingController();
  final latitude = TextEditingController(), longitude = TextEditingController();
  final hours = {
    for (final k in ['sunrise', 'noon', 'sunset']) k: TextEditingController(),
  };
  List<City>? cities;
  List<City> found = const [];
  String? message, clockMessage;
  String? zone;
  bool byHand = false, useClock = false, confirmClear = false, locating = false;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    zone = s.location?.zone ?? tz.local.name;
    final h = s.clockHours;
    useClock = h != null;
    if (h != null) {
      String f(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      hours['sunrise']!.text = f(h.sunrise);
      hours['noon']!.text = f(h.noon);
      hours['sunset']!.text = f(h.sunset);
    }
  }

  @override
  void dispose() {
    for (final c in [search, latitude, longitude, ...hours.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search(String text) async {
    final state = AppScope.read(context);
    cities ??= await state.cities();
    if (!mounted) return;
    setState(() => found = text.trim().isEmpty ? const [] : searchCities(cities!, state.folder!, text));
  }

  Future<void> _use(Place? place) async {
    await AppScope.read(context).setLocation(place);
    search.clear();
    setState(() {
      found = const [];
      message = null;
    });
  }

  Future<void> _locate() async {
    setState(() {
      locating = true;
      message = null;
    });
    final problem = await AppScope.read(context).useDeviceLocation();
    if (!mounted) return;
    setState(() {
      locating = false;
      message = problem;
    });
  }

  Future<void> _setReminder(String key, bool on) async {
    await AppScope.read(context).setReminder(key, on);
    if (on && mounted) await offerExactTimes(context);
  }

  void _applyCoordinates() {
    final lat = double.tryParse(latitude.text.trim()), lon = double.tryParse(longitude.text.trim());
    if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      setState(() => message = 'Enter a latitude from -90 to 90 and a longitude from -180 to 180.');
      return;
    }
    final place = Place.clean({'label': '', 'lat': lat, 'lon': lon, 'tz': zone});
    if (place == null) {
      setState(() => message = 'Choose a time zone.');
      return;
    }
    _use(place);
    latitude.clear();
    longitude.clear();
  }

  Future<void> _applyClock() async {
    final state = AppScope.read(context);
    setState(() => clockMessage = null);
    if (!useClock) return state.setClockHours(null);
    final h = ClockHours.clean({for (final e in hours.entries) e.key: parseClock(e.value.text)});
    if (h == null) {
      setState(
        () => clockMessage = 'Enter all three as HH:MM, in order within one day: sunrise, noon, sunset. Until then the app follows the sun.',
      );
      return state.setClockHours(null);
    }
    await state.setClockHours(h);
  }

  String _summary(AppState state) {
    final place = state.settings.location;
    if (place == null) return 'No location set.';
    final sun = placeSun(place, dayOf(localNow(place)));
    return '${place.label}\nTime zone: ${place.zone}\n${sun == null ? 'Sun times are not available.' : sunSummary(sun, state.clock)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final p = ReaderColors.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.accentText),
      ),
    );
    Widget gap([double h = 8]) => SizedBox(height: h);
    Widget check(String label, bool value, ValueChanged<bool>? onChanged) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      value: value,
      title: Text(label, style: const TextStyle(fontSize: 14.5)),
      onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
    );
    Widget reminder(String key, String label, {bool enabled = true}) =>
        check(label, s.reminders[key] ?? false, enabled ? (v) => _setReminder(key, v) : null);
    final unavailable = state.notifier.unavailable;
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        heading('Location'),
        const Text('Used to work out sunrise, noon and sunset. It stays on this device and is never sent anywhere.'),
        gap(),
        SelectableText(_summary(state), style: dimStyle(context, size: 13.5)),
        gap(),
        if (state.locator != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: locating ? null : _locate,
              icon: locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 20),
              label: Text(locating ? 'Finding your location…' : 'Use my location'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Asks the phone once where you are, to about a kilometre. Or search for a city:',
              style: dimStyle(context, size: 13.5),
            ),
          ),
        ],
        TextField(
          controller: search,
          onChanged: _search,
          decoration: const InputDecoration(hintText: 'Type a city…', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        for (final c in found)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SideRow(
              onTap: () => _use(Place.clean({'label': c.label, 'lat': c.lat, 'lon': c.lon, 'tz': c.zone})),
              child: Text('${c.label} · ${c.zone}'),
            ),
          ),
        if (search.text.trim().isNotEmpty && found.isEmpty && cities != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No city matches “${search.text.trim()}”. You can enter its coordinates below.',
              style: dimStyle(context, size: 13.5),
            ),
          ),
        gap(),
        InkWell(
          onTap: () => setState(() => byHand = !byHand),
          child: Row(
            children: [
              Icon(byHand ? Icons.expand_more : Icons.chevron_right, size: 20),
              const Flexible(child: Text('Or enter latitude, longitude and time zone')),
            ],
          ),
        ),
        if (byHand) ...[
          gap(),
          TextField(
            controller: latitude,
            decoration: const InputDecoration(labelText: 'Latitude (north is positive)', hintText: '32.82'),
          ),
          gap(),
          TextField(
            controller: longitude,
            decoration: const InputDecoration(labelText: 'Longitude (east is positive)', hintText: '34.99'),
          ),
          gap(),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: zone ?? ''),
            optionsBuilder: (v) {
              final q = v.text.toLowerCase();
              return tz.timeZoneDatabase.locations.keys.where((z) => z.toLowerCase().contains(q)).take(30);
            },
            onSelected: (z) => zone = z,
            fieldViewBuilder: (context, controller, node, submit) => TextField(
              controller: controller,
              focusNode: node,
              onChanged: (v) => zone = validZone(v) ? v : null,
              decoration: const InputDecoration(labelText: 'Time zone'),
            ),
          ),
          gap(),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _applyCoordinates, child: const Text('Use these coordinates')),
          ),
        ],
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(message!, style: dimStyle(context, size: 13.5)),
          ),
        if (s.location != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: () => _use(null), child: const Text('Clear location')),
            ),
          ),
        heading('Clock times'),
        const Text(
          '$clockAssembly This app sets no hours of its own. Once set, they replace the sun for prayer times, '
          'the Fast, reminders and when the Badí‘ date changes.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: useClock,
          title: const Text('Use clock times instead of the sun'),
          onChanged: (v) {
            setState(() => useClock = v ?? false);
            _applyClock();
          },
        ),
        for (final (key, label) in const [
          ('sunrise', 'Sunrise hour'),
          ('noon', 'Noon hour'),
          ('sunset', 'Sunset hour'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: hours[key],
              onSubmitted: (_) => _applyClock(),
              decoration: InputDecoration(labelText: label, hintText: 'HH:MM'),
            ),
          ),
        if (clockMessage != null) Text(clockMessage!, style: dimStyle(context, size: 13.5)),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _applyClock, child: const Text('Use these times')),
        ),
        heading('Obligatory prayer'),
        const Text('Which prayer you say. Its times then appear on Today.'),
        gap(),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (key, label) in const [
              ('short', 'Short'),
              ('medium', 'Medium'),
              ('long', 'Long'),
              ('none', 'Don’t track'),
            ])
              TextButton(
                onPressed: () => state.setPrayer(key),
                style: TextButton.styleFrom(
                  backgroundColor: (s.prayer ?? 'none') == key
                      ? p.foreground.withValues(alpha: 0.2)
                      : p.foreground.withValues(alpha: 0.07),
                ),
                child: Text(label),
              ),
          ],
        ),
        if (s.prayer != 'long')
          reminder('prayer', 'Remind me when its time opens and before it closes', enabled: isTracked(s.prayer)),
        if (s.prayer == 'long') ...[
          gap(12),
          const Text(
            'No text says which twenty-four hours are meant, and the House of Justice has made no ruling, so this '
            'is your choice. Sunset to sunset is the Bahá’í day the app’s date already follows.',
          ),
          RadioGroup<String>(
            groupValue: longPeriod(s.longPeriod),
            onChanged: (v) => v == null ? null : state.setLongPeriod(v),
            child: Column(
              children: [
                for (final (key, label) in longPeriods)
                  RadioListTile<String>(value: key, title: Text(label), contentPadding: EdgeInsets.zero, dense: true),
              ],
            ),
          ),
          reminder('long', 'Remind me once before the period resets, if it isn’t marked'),
          Row(
            children: [
              DropdownButton<int>(
                value: longLead(s.longLeadHours),
                underline: const SizedBox(),
                items: [for (var h = longLeadMin; h <= longLeadMax; h++) DropdownMenuItem(value: h, child: Text('$h'))],
                onChanged: (h) => h == null ? null : state.setLongLead(h),
              ),
              const SizedBox(width: 8),
              const Text('hours before'),
            ],
          ),
        ],
        gap(4),
        Text(
          'Without a location, reminders use clock times. Add a location and they follow the sun.',
          style: dimStyle(context, size: 13.5),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.keepRecords,
          title: const Text('Keep a private record of “Said today” and “Fasted today” on this device'),
          onChanged: (v) => state.setKeepRecords(v ?? true),
        ),
        const Text('These records are never sent anywhere. There are no scores or streaks.'),
        gap(),
        Wrap(
          spacing: 8,
          children: [
            if (!confirmClear)
              OutlinedButton(
                onPressed: () => setState(() => confirmClear = true),
                child: const Text('Clear my records'),
              )
            else ...[
              OutlinedButton(
                onPressed: () {
                  state.clearRecords();
                  setState(() => confirmClear = false);
                },
                child: const Text('Yes, clear them'),
              ),
              OutlinedButton(onPressed: () => setState(() => confirmClear = false), child: const Text('Keep them')),
            ],
          ],
        ),
        heading('Feasts, Holy Days and the Fast'),
        reminder('feast', 'Nineteen Day Feasts, on the afternoon of the day each begins'),
        reminder('holy', 'Holy Days, the day before and on the day'),
        reminder('fast', 'The Fast, 5, 3 and 1 days before it begins'),
        reminder('fast_daily', 'During the Fast, before sunrise and at sunset each day'),
        if (state.notifier.schedules)
          Text(
            'Reminders are set a week ahead and arrive even when the app is closed. Opening the app sets the next week.',
            style: dimStyle(context, size: 13.5),
          ),
        if (unavailable != null) Text(unavailable, style: dimStyle(context, size: 13.5)),
        if (state.remindersMayBeLate) ...[
          gap(),
          Text(
            'Android may hold reminders back by up to an hour. Allow “Alarms & reminders” so they arrive at the minute.',
            style: dimStyle(context, size: 13.5),
          ),
          gap(4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => state.notifier.requestExactTimes(),
              child: const Text('Allow reminders on time'),
            ),
          ),
        ],
        if (state.autostart != null) ...[
          check('Keep reminders running when the window is closed', s.keepRunning, state.setKeepRunning),
          Text(
            'A quiet background process starts when you log in and has no tray icon. Turn this off to stop it.',
            style: dimStyle(context, size: 13.5),
          ),
          if (state.keepRunningMessage case final m?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(m, style: dimStyle(context, size: 13.5)),
            ),
        ],
      ],
    );
    if (widget.page) {
      return Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(title: const Text('Location & reminders')),
        body: list,
      );
    }
    return Scaffold(
      backgroundColor: p.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeaderBar(
            title: const WindowTitle(title: 'Location & reminders'),
            end: [HeaderButton(icon: Icons.close, tooltip: 'Close', onPressed: () => Navigator.pop(context))],
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}
