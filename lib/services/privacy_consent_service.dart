import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

/// Optional product-analytics / non-essential data preference (Botswana DPA).
class PrivacyConsentService {
  static const _key = 'jobsy_analytics_consent';

  static Future<bool?> read() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_key)) return null;
    return prefs.getBool(_key);
  }

  static Future<void> setAccepted(bool accepted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, accepted);
  }

  static Future<void> openPrivacyPolicy() =>
      _open('${AppConstants.websiteUrl}/privacy.html');

  static Future<void> openTerms() =>
      _open('${AppConstants.websiteUrl}/terms.html');

  static Future<void> openCookies() =>
      _open('${AppConstants.websiteUrl}/cookies.html');

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
