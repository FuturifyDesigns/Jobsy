import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/colors.dart';
import '../utils/error_messages.dart';

/// WhatsApp-style voice message bubble.
/// Shows play/pause button + progress bar + duration.
///
/// Note on waveforms: real per-message waveforms need decoding the audio
/// client-side (expensive) or pre-computing on upload (extra bandwidth).
/// We ship a stylized "bar pattern" that's static but visually convincing.
/// If you need real waveforms later, use `audio_waveforms` package with
/// pre-computed samples stored in `attachment_meta`.
class VoiceMessageBubble extends StatefulWidget {
  final String url;
  final int durationSeconds;
  final bool isMe;
  final Color accentColor;

  const VoiceMessageBubble({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.isMe,
    required this.accentColor,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _total = Duration(seconds: widget.durationSeconds);

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _total = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        setState(() => _isLoading = true);
        await _player.play(UrlSource(widget.url));
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  double get _progress {
    if (_total.inMilliseconds == 0) return 0;
    final p = _position.inMilliseconds / _total.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.isMe ? Colors.white : JobsyColors.textPrimary;
    final Color track = widget.isMe
        ? Colors.white.withOpacity(0.3)
        : JobsyColors.textTertiary.withOpacity(0.4);
    final Color fill = widget.isMe ? Colors.white : widget.accentColor;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          // Play / pause / loading button
          GestureDetector(
            onTap: _isLoading ? null : _toggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withOpacity(0.2)
                    : widget.accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: fg,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform-style progress bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      progress: _progress,
                      track: track,
                      fill: fill,
                    ),
                    size: const Size(double.infinity, 24),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isPlaying || _position > Duration.zero
                      ? _formatDuration(_position)
                      : _formatDuration(_total),
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withOpacity(0.75),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Static "bar" pattern that fills based on progress. Cheap, convincing,
/// zero extra bandwidth. 30 bars of varying heights seed the illusion.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color fill;

  _WaveformPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  // Fixed pseudo-random heights, 30 bars. Deterministic = stable visual.
  static const _heights = [
    0.35, 0.55, 0.75, 0.9, 0.6, 0.4, 0.5, 0.7, 0.85, 0.65,
    0.3, 0.45, 0.6, 0.8, 0.9, 0.7, 0.55, 0.4, 0.5, 0.65,
    0.8, 0.95, 0.7, 0.5, 0.35, 0.45, 0.6, 0.7, 0.55, 0.4,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final int n = _heights.length;
    final double gap = 2;
    final double totalGap = gap * (n - 1);
    final double barWidth = (size.width - totalGap) / n;
    final double progressX = size.width * progress;

    for (int i = 0; i < n; i++) {
      final double x = i * (barWidth + gap);
      final double h = _heights[i] * size.height;
      final double y = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(1.5),
      );
      final paint = Paint()
        ..color = (x + barWidth / 2 <= progressX) ? fill : track;
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track;
}
