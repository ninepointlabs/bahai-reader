import 'package:flutter/services.dart';

/// One reading of where the device is, for sunrise and sunset ("Use my location" in Location & reminders). Asked for
/// only when the person taps it; never tracked and never sent anywhere.
abstract class Locator {
  const Locator();

  /// (latitude, longitude), or the reason there is none, ready to show.
  Future<({double lat, double lon})?> locate(void Function(String problem) onProblem);
}

/// Android (android/app/src/main/kotlin/.../Locate.kt): the phone's own location service, approximate permission only.
class AndroidLocator extends Locator {
  const AndroidLocator();
  static const _channel = MethodChannel('bahai_reader/location');

  @override
  Future<({double lat, double lon})?> locate(void Function(String problem) onProblem) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('locate');
      final lat = r?['lat'], lon = r?['lon'];
      if (lat is num && lon is num) return (lat: lat.toDouble(), lon: lon.toDouble());
      onProblem(r?['error'] as String? ?? 'Couldn’t find where you are.');
    } on PlatformException catch (e) {
      onProblem(e.message ?? 'Couldn’t find where you are.');
    } on MissingPluginException {
      onProblem('Finding your location isn’t available here.');
    }
    return null;
  }
}
