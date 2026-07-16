import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/colors.dart';
import '../screens/chat/pdf_viewer_screen.dart';
import '../services/application_ranking_service.dart';
import '../utils/error_messages.dart';

/// Opens application qualification files in-app when possible.
class ApplicationQualificationViewer {
  ApplicationQualificationViewer._();

  static Future<void> open(
    BuildContext context, {
    required String storagePath,
    required String fileName,
  }) async {
    try {
      final url = await Supabase.instance.client.storage
          .from('application-qualifications')
          .createSignedUrl(storagePath, 3600);
      if (!context.mounted) return;

      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

      if (ext == 'pdf') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(url: url, filename: fileName),
          ),
        );
        return;
      }

      if (const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
        await Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (_, __, ___) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded,
                          color: Colors.white, size: 60),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }

      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this file.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  static List<Map<String, String>> parseFiles(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final items = <Map<String, String>>[];
    for (final e in raw) {
      if (e is Map) {
        final path = e['path']?.toString();
        final name = e['name']?.toString() ?? 'Document';
        if (path != null && path.isNotEmpty) {
          items.add({'path': path, 'name': name});
        }
      }
    }
    return items;
  }
}

/// Bottom sheet with the full application payload for employer review.
class ApplicationDetailSheet extends StatelessWidget {
  final Map<String, dynamic> application;
  final Map<String, dynamic>? worker;
  final ApplicationRankResult? rank;

  const ApplicationDetailSheet({
    super.key,
    required this.application,
    this.worker,
    this.rank,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> application,
    Map<String, dynamic>? worker,
    ApplicationRankResult? rank,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApplicationDetailSheet(
        application: application,
        worker: worker,
        rank: rank,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = ApplicationQualificationViewer.parseFiles(
      application['qualification_files'],
    );
    final name = worker?['full_name']?.toString() ?? 'Applicant';

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: JobsyColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$name — application',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: JobsyColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (rank != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RankBanner(rank: rank!),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _section('Cover letter', application['cover_letter']?.toString()),
                  _section('References', application['references_text']?.toString()),
                  _section('Additional details', application['additional_info']?.toString()),
                  if (files.isNotEmpty) ...[
                    const Text(
                      'Uploaded files',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: JobsyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...files.map((f) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: JobsyColors.surface,
                        child: ListTile(
                          leading: Icon(
                            f['name']!.toLowerCase().endsWith('.pdf')
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                            color: JobsyColors.employerPrimary,
                          ),
                          title: Text(f['name']!,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                          onTap: () => ApplicationQualificationViewer.open(
                            context,
                            storagePath: f['path']!,
                            fileName: f['name']!,
                          ),
                        ),
                      );
                    }),
                  ],
                  if (worker != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Worker profile',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: JobsyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (worker!['experience_level'] != null)
                      Text('Experience: ${worker!['experience_level']}',
                          style: const TextStyle(color: JobsyColors.textSecondary)),
                    if (worker!['location'] != null)
                      Text('Location: ${worker!['location']}',
                          style: const TextStyle(color: JobsyColors.textSecondary)),
                    if (worker!['hourly_rate'] != null)
                      Text(
                        'Hourly rate: P${(worker!['hourly_rate'] as num).toStringAsFixed(0)}',
                        style: const TextStyle(color: JobsyColors.textSecondary),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String? body) {
    final text = body?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: JobsyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: JobsyColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBanner extends StatelessWidget {
  final ApplicationRankResult rank;

  const _RankBanner({required this.rank});

  Color get _color {
    if (rank.isStrong) return const Color(0xFF10B981);
    if (rank.isGood) return JobsyColors.employerPrimary;
    if (rank.isFair) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Jobsy helper · ${rank.tier}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _color,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${rank.score}/100',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (rank.pros.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...rank.pros.take(3).map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 16, color: _color.withOpacity(0.9)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(p,
                              style: const TextStyle(
                                  fontSize: 12.5, color: JobsyColors.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (rank.cons.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...rank.cons.take(2).map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: JobsyColors.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c,
                              style: const TextStyle(
                                  fontSize: 12.5, color: JobsyColors.textTertiary)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
