import 'dart:convert';

import '../search/fold.dart';

/// A city from the bundled GeoNames list (cities of 15,000 people or more, © GeoNames, CC BY 4.0).
class City {
  const City(this.name, this.ascii, this.label, this.lat, this.lon, this.zone);
  final String name, ascii, label, zone;
  final double lat, lon;
}

/// The bundled city list, largest first (GTK `load_cities()`).
List<City> parseCities(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final regions = (data['regions'] as List).cast<String>();
  final zones = (data['zones'] as List).cast<String>();
  final countries = (data['countries'] as Map).cast<String, String>();
  final rows = <City>[];
  for (final line in (data['cities'] as String).split(';')) {
    final f = line.split('|');
    if (f.length != 7) continue;
    final region = regions[int.parse(f[3])];
    final seen = <String>{};
    final label = [f[0], region, countries[f[2]] ?? f[2]].where((s) => s.isNotEmpty && seen.add(s)).join(', ');
    rows.add(City(f[0], f[1].isEmpty ? f[0] : f[1], label, double.parse(f[4]), double.parse(f[5]), zones[int.parse(f[6])]));
  }
  return rows;
}

/// Places matching what was typed, without regard to accents: exact names, then names starting with it, then any word
/// starting with it, then anything containing it; largest first within each. "Paris, Texas" narrows by region or country.
List<City> searchCities(List<City> cities, Folder folder, String query, {int limit = 8}) {
  final cut = query.indexOf(',');
  final city = folder.fold((cut < 0 ? query : query.substring(0, cut)).trim());
  final rest = cut < 0 ? '' : folder.fold(query.substring(cut + 1).trim());
  if (city.isEmpty) return [];
  final found = [<City>[], <City>[], <City>[], <City>[]];
  for (final row in cities) {
    final names = [folder.fold(row.name), folder.fold(row.ascii)];
    if (!names.any((n) => n.contains(city))) continue;
    if (rest.isNotEmpty && !folder.fold(row.label).contains(rest)) continue;
    final int rank;
    if (names.contains(city)) {
      rank = 0;
    } else if (names.any((n) => n.startsWith(city))) {
      rank = 1;
    } else if (names.any((n) => n.split(' ').any((w) => w.startsWith(city)))) {
      rank = 2;
    } else {
      rank = 3;
    }
    found[rank].add(row);
  }
  return found.expand((r) => r).take(limit).toList();
}
