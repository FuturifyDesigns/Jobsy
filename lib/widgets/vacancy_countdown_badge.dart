import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../utils/external_job_presentation.dart';

/// Live vacancy countdown chip for external job listings.
class VacancyCountdownBadge extends StatelessWidget {
  final Map<String, dynamic> job;
  final DateTime now;
  final bool compact;

  const VacancyCountdownBadge({
    super.key,
    required this.job,
    required this.now,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = ExternalJobPresentation.vacancyCountdownLabel(job, now: now);
    final urgency = ExternalJobPresentation.vacancyUrgency(job, now: now);
    final colors = _colorsFor(urgency);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            urgency == VacancyUrgency.closed ? Icons.event_busy_rounded : Icons.schedule_rounded,
            size: compact ? 12 : 13,
            color: colors.foreground,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  _BadgeColors _colorsFor(VacancyUrgency urgency) {
    switch (urgency) {
      case VacancyUrgency.closed:
        return _BadgeColors(
          background: Colors.grey.withValues(alpha: 0.15),
          border: Colors.grey.withValues(alpha: 0.35),
          foreground: JobsyColors.textTertiary,
        );
      case VacancyUrgency.critical:
        return _BadgeColors(
          background: Colors.red.withValues(alpha: 0.12),
          border: Colors.red.withValues(alpha: 0.35),
          foreground: Colors.red.shade700,
        );
      case VacancyUrgency.soon:
        return _BadgeColors(
          background: Colors.orange.withValues(alpha: 0.12),
          border: Colors.orange.withValues(alpha: 0.35),
          foreground: Colors.orange.shade800,
        );
      case VacancyUrgency.comfortable:
        return _BadgeColors(
          background: Colors.green.withValues(alpha: 0.12),
          border: Colors.green.withValues(alpha: 0.3),
          foreground: Colors.green.shade700,
        );
      case VacancyUrgency.open:
        return _BadgeColors(
          background: JobsyColors.workerPrimary.withValues(alpha: 0.1),
          border: JobsyColors.workerPrimary.withValues(alpha: 0.28),
          foreground: JobsyColors.workerPrimary,
        );
    }
  }
}

class _BadgeColors {
  final Color background;
  final Color border;
  final Color foreground;

  const _BadgeColors({
    required this.background,
    required this.border,
    required this.foreground,
  });
}
