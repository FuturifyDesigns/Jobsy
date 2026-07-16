import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/colors.dart';
import '../widgets/rating_dialog.dart';

/// Shows when the user returns after someone left a new rating for them.
/// If they haven't rated back yet, prompts them to do so immediately.
class NewRatingPopupService {
  static const _watermarkKey = 'jobsy_rating_prompt_watermark';

  static Future<void> check(BuildContext context, {required bool isEmployer}) async {
    final prefs = await SharedPreferences.getInstance();
    var watermark = prefs.getString(_watermarkKey);
    if (watermark == null) {
      watermark = DateTime.now().toUtc().toIso8601String();
      await prefs.setString(_watermarkKey, watermark);
      return;
    }

    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null || !context.mounted) return;

    final row = await Supabase.instance.client
        .from('ratings')
        .select(
          'id, rating, review, created_at, rater_id, job_id, application_id',
        )
        .eq('rated_id', myId)
        .gt('created_at', watermark)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null || !context.mounted) return;

    final raterId = row['rater_id'] as String?;
    final jobId = row['job_id'] as String?;
    final applicationId = row['application_id'] as String?;
    final stars = (row['rating'] as num?)?.toInt() ?? 0;
    final createdAt = row['created_at'] as String?;

    if (raterId == null ||
        jobId == null ||
        applicationId == null ||
        applicationId.isEmpty) {
      await _advanceWatermark(prefs, createdAt);
      return;
    }

    final alreadyRatedBack = await Supabase.instance.client
        .from('ratings')
        .select('id')
        .eq('rater_id', myId)
        .eq('application_id', applicationId)
        .maybeSingle();

    String raterName = 'Someone';
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', raterId)
          .maybeSingle();
      raterName = p?['full_name'] as String? ?? raterName;
    } catch (_) {}

    String jobTitle = 'your job';
    try {
      final j = await Supabase.instance.client
          .from('jobs')
          .select('title')
          .eq('id', jobId)
          .maybeSingle();
      jobTitle = j?['title'] as String? ?? jobTitle;
    } catch (_) {}

    if (!context.mounted) return;

    final accent =
        isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

    if (alreadyRatedBack == null) {
      final rateNow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: JobsyColors.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Icon(Icons.star_rounded, color: accent, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'You were rated!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$raterName gave you $stars star${stars == 1 ? '' : 's'} for “$jobTitle”.',
                style: const TextStyle(
                  fontSize: 14,
                  color: JobsyColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 26,
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text(
                isEmployer
                    ? 'Rate $raterName back to complete the review.'
                    : 'Rate $raterName back now — your turn!',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: JobsyColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: JobsyColors.roleFilledButtonStyle(accent),
              child: Text(isEmployer ? 'Rate worker' : 'Rate employer'),
            ),
          ],
        ),
      );

      if (rateNow == true && context.mounted) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => RatingDialog(
            jobTitle: jobTitle,
            ratedUserId: raterId,
            ratedUserName: raterName,
            jobId: jobId,
            applicationId: applicationId,
            isRatingWorker: isEmployer,
          ),
        );
      }
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: JobsyColors.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'You were rated',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: JobsyColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$raterName gave you $stars star${stars == 1 ? '' : 's'} for “$jobTitle”.',
                style: const TextStyle(
                  fontSize: 14,
                  color: JobsyColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 26,
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    await _advanceWatermark(prefs, createdAt);
  }

  static Future<void> _advanceWatermark(
    SharedPreferences prefs,
    String? createdAt,
  ) async {
    if (createdAt != null) {
      await prefs.setString(_watermarkKey, createdAt);
    }
  }
}
