import 'dart:convert';

/// Credentials are stored XOR+Base64 encoded so they do not appear as
/// plain strings in the compiled binary or in source search tools.
///
/// To rebuild the encoded values (e.g. after rotating keys), run:
///   dart scripts/encode_secrets.dart <supabase-url> <anon-key>
/// and paste the output below.
///
/// For release builds, override via --dart-define to keep values out of
/// source entirely:
///   flutter build apk --release
///     --dart-define=SUPABASE_URL=<encoded>
///     --dart-define=SUPABASE_ANON_KEY=<encoded>
class Env {
  Env._();

  // Encoded defaults — used when --dart-define is not provided (e.g. IDE runs).
  // Override at build time with --dart-define=SUPABASE_URL=... for CI/release.
  static const String _rawUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'IhsWAwobb2UFFAYVRywvAwcKG0IvJgUBHglWMWQcFwMYQyE5CkwQFg',
  );
  static const String _rawKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'LxYoGxtmIyMgCzkwdDoDXiwaMFIJJD1XEDpodgMEEisvYgpzQQcKM1EjeSILPBBrOi43IBsgTAYwNTE6CmguAAM4GjAXCScfUBcuWS0oKDQAI3ksIzZQSgpALQQbATsdWQkjGAsQFBgzEDwrRTBMBj8NUEcQbQMAHzsrKEgPICpRPRNGcwQrI0c2ZSc5Jg8lTUIDA1kvGTgVDg4iGj0TRnQFJ1JdTGwiBzk3HwpDCCFcC14AFiQjNgwdKhVwPzwzQRhiciMOLDYSRQYYNls3Gg',
  );

  /// Google OAuth Web Client ID (from Google Cloud / Firebase).
  /// Encode with: dart scripts/encode_secrets.dart <url> <anon-key> <google-web-client-id>
  /// Pass via: --dart-define=GOOGLE_WEB_CLIENT_ID=<encoded>
  static const String _rawGoogleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        'c1dQR00Xd31YVkRJDDR7CBEAFRF5J1ZbQk4QLS8DUBkfU3UpXBFDD1EiLFZQXRhRMDlBBRwWRiwvGhEWC0IvJBsHHQ0PIyUC',
  );

  /// XOR salt — must match encode_secrets.dart.
  static const List<int> _salt = [0x4A, 0x6F, 0x62, 0x73, 0x79, 0x21, 0x40];

  static String get supabaseUrl => _decode(_rawUrl);
  static String get supabaseAnonKey => _decode(_rawKey);
  static String get googleWebClientId => _decode(_rawGoogleWebClientId);

  static String _decode(String encoded) {
    if (encoded.isEmpty) return '';
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      final decoded = List<int>.generate(
        bytes.length,
        (i) => bytes[i] ^ _salt[i % _salt.length],
      );
      return utf8.decode(decoded);
    } catch (_) {
      return encoded;
    }
  }
}
