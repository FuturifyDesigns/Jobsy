import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads compressed profile images to Supabase Storage (free-tier friendly).
///
/// Uses the public `avatars` bucket with one file per user per type:
/// `{userId}/avatar.jpg` and `{userId}/cover.jpg` (upsert — no orphaned files).
class ProfileImageService {
  ProfileImageService._();

  static const String bucket = 'avatars';

  /// Hard caps keep storage and bandwidth low on Supabase free tier.
  static const int maxCoverBytes = 350 * 1024;
  static const int maxAvatarBytes = 200 * 1024;

  static String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  static Future<Uint8List> _compressCover(String path) async {
    var bytes = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 1200,
      minHeight: 600,
      quality: 72,
      format: CompressFormat.jpeg,
    );
    bytes ??= await File(path).readAsBytes();

    if (bytes.length > maxCoverBytes) {
      bytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1000,
        minHeight: 500,
        quality: 55,
        format: CompressFormat.jpeg,
      );
    }
    if (bytes.length > maxCoverBytes) {
      throw Exception(
        'Cover image is too large after compression. Try a simpler photo.',
      );
    }
    return bytes;
  }

  static Future<Uint8List> _compressAvatar(String path) async {
    var bytes = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 512,
      minHeight: 512,
      quality: 75,
      format: CompressFormat.jpeg,
    );
    bytes ??= await File(path).readAsBytes();

    if (bytes.length > maxAvatarBytes) {
      bytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 400,
        minHeight: 400,
        quality: 60,
        format: CompressFormat.jpeg,
      );
    }
    if (bytes.length > maxAvatarBytes) {
      throw Exception(
        'Profile photo is too large after compression. Try a smaller image.',
      );
    }
    return bytes;
  }

  static Future<String> _uploadJpeg({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    await Supabase.instance.client.storage.from(bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final baseUrl =
        Supabase.instance.client.storage.from(bucket).getPublicUrl(storagePath);
    return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  static Future<String> uploadCover(XFile picked) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not signed in');

    final bytes = await _compressCover(picked.path);
    final url = await _uploadJpeg(
      storagePath: '$userId/cover.jpg',
      bytes: bytes,
    );

    await Supabase.instance.client
        .from('profiles')
        .update({'cover_url': url})
        .eq('id', userId);

    return url;
  }

  static Future<void> removeCover() async {
    final userId = _userId;
    if (userId == null) throw Exception('Not signed in');

    try {
      await Supabase.instance.client.storage
          .from(bucket)
          .remove(['$userId/cover.jpg']);
    } catch (_) {}

    await Supabase.instance.client
        .from('profiles')
        .update({'cover_url': null})
        .eq('id', userId);
  }

  static Future<String> uploadAvatar(XFile picked) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not signed in');

    final bytes = await _compressAvatar(picked.path);
    final url = await _uploadJpeg(
      storagePath: '$userId/avatar.jpg',
      bytes: bytes,
    );

    await Supabase.instance.client
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', userId);

    return url;
  }

  static Future<void> removeAvatar() async {
    final userId = _userId;
    if (userId == null) throw Exception('Not signed in');

    try {
      await Supabase.instance.client.storage
          .from(bucket)
          .remove(['$userId/avatar.jpg']);
    } catch (_) {}

    await Supabase.instance.client
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', userId);
  }
}
