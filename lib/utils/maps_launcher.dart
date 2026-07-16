import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps with an exact pin or verbatim posted address.
class MapsLauncher {
  MapsLauncher._();

  /// Opens directions to the exact GPS coordinates stored on a job post.
  static Future<bool> openCoordinates(double lat, double lng) async {
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final dirUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    try {
      if (await canLaunchUrl(geoUri)) {
        return launchUrl(geoUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return launchUrl(dirUri, mode: LaunchMode.externalApplication);
  }

  /// Fallback when no GPS pin exists — uses only the text the poster entered.
  static Future<bool> openPostedText(String location) async {
    final query = location.trim();
    if (query.isEmpty) return false;

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(query)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// @deprecated Use [openPostedText]. Kept for external/web jobs without coords.
  static Future<bool> openLocation(
    String location, {
    String? near,
  }) =>
      openPostedText(location);

  static bool hasJobCoordinates(Map<String, dynamic> job) {
    final lat = (job['latitude'] as num?)?.toDouble();
    final lng = (job['longitude'] as num?)?.toDouble();
    return lat != null &&
        lng != null &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
  }

  /// Exact GPS pin when coordinates exist; otherwise verbatim posted address.
  static Future<bool> openJobLocation(Map<String, dynamic> job) async {
    final lat = (job['latitude'] as num?)?.toDouble();
    final lng = (job['longitude'] as num?)?.toDouble();
    if (lat != null &&
        lng != null &&
        lat.abs() <= 90 &&
        lng.abs() <= 180) {
      return openCoordinates(lat, lng);
    }
    final loc = job['location']?.toString().trim() ?? '';
    if (loc.isEmpty) return false;
    return openPostedText(loc);
  }
}
