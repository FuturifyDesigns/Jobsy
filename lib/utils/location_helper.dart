import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Reverse-geocode device GPS into a human-readable area string.
class LocationHelper {
  LocationHelper._();

  static Future<String?> getCurrentAreaLabel() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );

    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (placemarks.isEmpty) return null;

    final p = placemarks.first;
    final parts = <String>[
      if (p.locality != null && p.locality!.trim().isNotEmpty) p.locality!.trim(),
      if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty)
        p.administrativeArea!.trim(),
      if (p.country != null && p.country!.trim().isNotEmpty) p.country!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}
