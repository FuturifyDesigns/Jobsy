import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/colors.dart';
import '../config/constants.dart';
import '../services/ui_feedback.dart';

class RatingDialog extends StatefulWidget {
  final String jobTitle;
  final String ratedUserId;
  final String ratedUserName;
  final String jobId;
  final String applicationId;
  final String? conversationId;

  /// true  = employer rating the worker
  /// false = worker rating the employer
  final bool isRatingWorker;

  const RatingDialog({
    super.key,
    required this.jobTitle,
    required this.ratedUserId,
    required this.ratedUserName,
    required this.jobId,
    required this.applicationId,
    this.conversationId,
    required this.isRatingWorker,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _selectedRating = 0;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Color get _accent =>
      widget.isRatingWorker ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  String get _title =>
      widget.isRatingWorker ? 'Rate the Worker' : 'Rate the Employer';

  String get _subtitle =>
      widget.isRatingWorker
          ? 'How did ${widget.ratedUserName} do on "${widget.jobTitle}"?'
          : 'How was your experience with ${widget.ratedUserName}?';

  Future<void> _submit() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;
      if (myId == widget.ratedUserId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You cannot rate yourself.'),
              backgroundColor: JobsyColors.error,
            ),
          );
          setState(() => _isSubmitting = false);
        }
        return;
      }
      await Supabase.instance.client.from('ratings').insert({
        'rater_id': myId,
        'rated_id': widget.ratedUserId,
        'job_id': widget.jobId,
        'application_id': widget.applicationId,
        'rating': _selectedRating,
        'review': _reviewController.text.trim().isEmpty
            ? null
            : _reviewController.text.trim(),
      });

      // Notify the rated user in real-time
      try {
        final myProfile = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', myId)
            .maybeSingle();
        final myName = myProfile?['full_name'] as String? ?? 'Someone';
        final stars = _selectedRating;
        await Supabase.instance.client.from('notifications').insert({
          'user_id': widget.ratedUserId,
          'type': 'new_rating',
          'title': 'You received a rating! ⭐',
          'body':
              '$myName gave you $stars star${stars == 1 ? '' : 's'} for "${widget.jobTitle}"',
          'target_role': widget.isRatingWorker
              ? AppConstants.userTypeWorker
              : AppConstants.userTypeEmployer,
          'related_job_id': widget.jobId,
          'related_application_id': widget.applicationId,
          'related_user_id': myId,
          if (widget.conversationId != null &&
              widget.conversationId!.isNotEmpty)
            'related_conversation_id': widget.conversationId,
        });
      } catch (_) {} // notifications are best-effort

      await UiSounds.success();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        await UiSounds.error();
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit rating. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: JobsyColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.star_rounded, color: _accent, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            _title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: JobsyColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            _subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: JobsyColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Star selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starValue = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selectedRating = starValue),
                child: AnimatedScale(
                  scale: _selectedRating >= starValue ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      _selectedRating >= starValue
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: _selectedRating >= starValue
                          ? Colors.amber
                          : JobsyColors.textTertiary,
                      size: 40,
                    ),
                  ),
                ),
              );
            }),
          ),

          // Rating label
          if (_selectedRating > 0) ...[
            const SizedBox(height: 8),
            Text(
              ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'][_selectedRating],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Optional review
          TextField(
            controller: _reviewController,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(fontSize: 14, color: JobsyColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Leave a review (optional)…',
              hintStyle: const TextStyle(
                  color: JobsyColors.textTertiary, fontSize: 14),
              filled: true,
              fillColor: JobsyColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: JobsyColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: JobsyColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accent, width: 2),
              ),
              counterStyle: const TextStyle(
                  color: JobsyColors.textTertiary, fontSize: 11),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Skip',
              style: TextStyle(color: JobsyColors.textTertiary)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
            style: JobsyColors.roleFilledButtonStyle(_accent, radius: 12),
          child: _isSubmitting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: JobsyColors.onRoleAccent(_accent),
                    strokeWidth: 2,
                  ),
                )
              : const Text('Submit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
