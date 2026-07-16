import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../config/colors.dart';

/// WhatsApp-style press-and-hold voice recorder.
///
/// Callback pattern:
///   onStart → begins recording, overlay appears
///   onCancel → recording dropped (slide-left gesture, or explicit cancel)
///   onComplete → recording finished, returns (filePath, durationSeconds)
///
/// Storage-tier friendly:
///   - AAC-LC @ 24 kbps mono, 22.05 kHz = ~10 KB/s
///   - 3-minute hard cap (auto-stops + submits)
///   - Minimum 1-second guard (below this → cancel, not submit)
class VoiceRecorderController {
  final AudioRecorder _rec = AudioRecorder();
  String? _currentPath;
  DateTime? _startedAt;
  Timer? _tick;

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<bool> start() async {
    if (isRecording) return false;
    try {
      if (!await _rec.hasPermission()) return false;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 24000,        // 24 kbps — WhatsApp uses 16, 24 is our safety margin
          sampleRate: 22050,     // half of standard 44.1 — voice doesn't need more
          numChannels: 1,        // mono
        ),
        path: path,
      );
      _currentPath = path;
      _startedAt = DateTime.now();
      return true;
    } catch (_) {
      _currentPath = null;
      _startedAt = null;
      return false;
    }
  }

  /// Returns (path, seconds) on success, null if recording was too short or failed.
  Future<(String, int)?> stop() async {
    if (!isRecording) return null;
    try {
      final path = await _rec.stop();
      final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
      _startedAt = null;
      _tick?.cancel();

      if (path == null) return null;
      // Guard: anything under 1 second is probably a fat-finger tap
      if (elapsed < 1000) {
        try { await File(path).delete(); } catch (_) {}
        return null;
      }
      return (path, (elapsed / 1000).round());
    } catch (_) {
      _startedAt = null;
      return null;
    }
  }

  Future<void> cancel() async {
    if (!isRecording) return;
    try {
      await _rec.cancel();
    } catch (_) {}
    _startedAt = null;
    _tick?.cancel();
    if (_currentPath != null) {
      try { await File(_currentPath!).delete(); } catch (_) {}
      _currentPath = null;
    }
  }

  void dispose() {
    _tick?.cancel();
    _rec.dispose();
  }
}

/// The overlay shown above the composer while recording.
/// Displays a pulsing red dot, elapsed time, and a "slide to cancel" hint.
class RecordingOverlay extends StatefulWidget {
  final DateTime startedAt;
  final double slideOffset;   // 0 = idle, negative = user dragged left
  final bool cancelArmed;     // true when slide exceeded cancel threshold
  final int maxSeconds;

  const RecordingOverlay({
    super.key,
    required this.startedAt,
    this.slideOffset = 0,
    this.cancelArmed = false,
    this.maxSeconds = 180,
  });

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.startedAt);
      });
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.cancelArmed ? JobsyColors.error : const Color(0xFFEF4444);
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing red dot
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Elapsed time
          Text(
            _formatDuration(_elapsed),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: JobsyColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          // Slide to cancel hint
          Transform.translate(
            offset: Offset(widget.slideOffset.clamp(-80, 0), 0),
            child: Opacity(
              opacity: widget.cancelArmed ? 0.4 : 1.0,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    color: JobsyColors.textTertiary,
                    size: 18,
                  ),
                  Text(
                    'Slide to cancel',
                    style: TextStyle(
                      color: JobsyColors.textTertiary,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
