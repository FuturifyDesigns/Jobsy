/// Run locally to encode credentials before passing to `--dart-define`.
///
/// Usage:
///   dart scripts/encode_secrets.dart <supabase-url> <anon-key> [google-web-client-id]
///
/// Copy output into build.bat / CI variables.

import 'dart:convert';
import 'dart:io';

const List<int> _salt = [0x4A, 0x6F, 0x62, 0x73, 0x79, 0x21, 0x40];

String encode(String value) {
  final bytes = utf8.encode(value);
  final xored = List<int>.generate(
    bytes.length,
    (i) => bytes[i] ^ _salt[i % _salt.length],
  );
  return base64Url.encode(xored).replaceAll('=', '');
}

void main(List<String> args) {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln(
      'Usage: dart scripts/encode_secrets.dart <supabase-url> <anon-key> [google-web-client-id]',
    );
    exit(1);
  }
  final url = encode(args[0]);
  final key = encode(args[1]);
  stdout.writeln('SUPABASE_URL (encoded):      $url');
  stdout.writeln('SUPABASE_ANON_KEY (encoded): $key');
  if (args.length == 3 && args[2].isNotEmpty) {
    final google = encode(args[2]);
    stdout.writeln('GOOGLE_WEB_CLIENT_ID (encoded): $google');
    stdout.writeln('');
    stdout.writeln('Release build:');
    stdout.writeln(
      '  flutter build apk --release --obfuscate --split-debug-info=debug_symbols '
      '--dart-define=SUPABASE_URL=$url '
      '--dart-define=SUPABASE_ANON_KEY=$key '
      '--dart-define=GOOGLE_WEB_CLIENT_ID=$google',
    );
  } else {
    stdout.writeln('');
    stdout.writeln('Release build:');
    stdout.writeln(
      '  flutter build apk --release --obfuscate --split-debug-info=debug_symbols '
      '--dart-define=SUPABASE_URL=$url --dart-define=SUPABASE_ANON_KEY=$key',
    );
  }
}
