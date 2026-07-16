import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../services/role_service.dart';
import '../../services/last_seen_pinger.dart';
import '../../utils/error_messages.dart';
import '../../widgets/voice_recorder.dart';
import '../../widgets/voice_bubble.dart';
import '../../widgets/rating_dialog.dart';
import 'pdf_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String? otherUserId;
  final String jobTitle;
  final bool isEmployer;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.otherUserId,
    required this.jobTitle,
    required this.isEmployer,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _voiceController = VoiceRecorderController();
  bool _isSending = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  double _recordSlideOffset = 0;
  bool _cancelArmed = false;
  // Locked recording: user slid up past the lock threshold and released.
  // While locked, the mic button is hidden and a dedicated bar with Stop +
  // Cancel buttons is shown. Recording continues hands-free.
  bool _isLocked = false;
  bool _lockArmed = false;       // true when the vertical drag has passed threshold
  double _recordSlideUpOffset = 0; // negative dy from start (upward = more negative)
  // Message currently being replied to (null = no active reply)
  Map<String, dynamic>? _replyingTo;
  // All messages currently on screen — used for reply-to lookup
  List<Map<String, dynamic>> _currentMessages = const [];
  RealtimeChannel? _channel;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _jobChannel; // real-time job status + worker_completed updates
  // Other user is typing right now
  bool _otherIsTyping = false;
  Timer? _typingDebounce;        // for firing our own typing broadcasts
  Timer? _otherTypingClearTimer; // clears the "other is typing" label
  DateTime? _lastTypingSent;
  // Other user is present in this conversation screen
  bool _otherIsPresent = false;
  // Other user's last_seen_at timestamp (UTC)
  DateTime? _otherLastSeen;
  String? _jobId;
  String? _applicationId;
  String? _jobStatus;
  bool _workerCompleted = false;
  bool _hasRated = false;
  /// Resolved from the conversation row — not profile user_type — so completion
  /// actions stay correct even if the user switched roles elsewhere.
  bool _isEmployerView = false;
  bool _roleResolved = false;
  String? _otherUserLocation;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;
  bool get _isEmployer => _roleResolved ? _isEmployerView : widget.isEmployer;
  Color get _primaryColor =>
      _isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _subscribeRealtime();
    _subscribePresence();
    _loadJobInfo();
    _pingLastSeen();        // update my last_seen on chat open
    _loadOtherLastSeen();   // fetch other user's last_seen once
    _loadOtherUserLocation();
    // Track whether the composer has text for the mic↔send swap
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
      if (hasText) _broadcastTyping();
    });
    // Close emoji panel when keyboard opens
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _otherTypingClearTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _voiceController.dispose();
    _channel?.unsubscribe();
    _presenceChannel?.unsubscribe();
    _jobChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadJobInfo() async {
    try {
      final conv = await Supabase.instance.client
          .from('conversations')
          .select('job_id, application_id, employer_id, worker_id')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (conv == null) return;

      if (mounted) {
        setState(() {
          _isEmployerView = conv['employer_id'] == _myId;
          _roleResolved = true;
        });
      }

      final jobId = conv['job_id'] as String?;
      final appId = conv['application_id'] as String?;

      if (jobId != null) {
        final job = await Supabase.instance.client
            .from('jobs')
            .select('id, status')
            .eq('id', jobId)
            .maybeSingle();
        if (mounted && job != null) {
          setState(() {
            _jobId = job['id'];
            _jobStatus = job['status'];
          });
        }
      }

      if (appId != null) {
        final app = await Supabase.instance.client
            .from('job_applications')
            .select('id, worker_completed')
            .eq('id', appId)
            .maybeSingle();
        if (mounted && app != null) {
          setState(() {
            _applicationId = app['id'];
            _workerCompleted = app['worker_completed'] == true;
          });
        }

        // Check if current user has already submitted a rating
        final existingRating = await Supabase.instance.client
            .from('ratings')
            .select('id')
            .eq('rater_id', _myId)
            .eq('application_id', appId)
            .maybeSingle();
        if (mounted) {
          setState(() => _hasRated = existingRating != null);
        }
      }

      // Start real-time subscription now that we have the IDs
      _subscribeToJobUpdates();
    } catch (e) {
      debugPrint('Load job info: $e');
    }
  }

  /// Subscribe to real-time changes on the job and application rows so the
  /// completion state and worker_completed flag update live without reloading.
  void _subscribeToJobUpdates() {
    if (_jobId == null && _applicationId == null) return;

    var channel = Supabase.instance.client
        .channel('job-updates:${widget.conversationId}');

    if (_jobId != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'jobs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _jobId!,
        ),
        callback: (payload) {
          final newStatus = payload.newRecord['status'] as String?;
          if (!mounted || newStatus == null) return;
          final wasCompleted = _jobStatus == 'completed';
          setState(() => _jobStatus = newStatus);
          // Worker: show rating prompt as soon as job flips to completed
          if (!wasCompleted &&
              newStatus == 'completed' &&
              !_isEmployer &&
              !_hasRated &&
              widget.otherUserId != null &&
              _applicationId != null) {
            _showWorkerRatingPrompt();
          }
        },
      );
    }

    if (_applicationId != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'job_applications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _applicationId!,
        ),
        callback: (payload) {
          final workerDone =
              payload.newRecord['worker_completed'] as bool? ?? false;
          if (mounted) setState(() => _workerCompleted = workerDone);
        },
      );
    }

    _jobChannel = channel..subscribe();
  }

  /// Called on the worker when the job transitions to completed in real-time.
  Future<void> _showWorkerRatingPrompt() async {
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RatingDialog(
        jobTitle: widget.jobTitle,
        ratedUserId: widget.otherUserId!,
        ratedUserName: widget.otherUserName,
        jobId: _jobId!,
        applicationId: _applicationId!,
        conversationId: widget.conversationId,
        isRatingWorker: false,
      ),
    );
    await _refreshHasRated();
  }

  Future<void> _refreshHasRated() async {
    final appId = _applicationId;
    if (appId == null || !mounted) return;
    try {
      final existingRating = await Supabase.instance.client
          .from('ratings')
          .select('id')
          .eq('rater_id', _myId)
          .eq('application_id', appId)
          .maybeSingle();
      if (mounted) setState(() => _hasRated = existingRating != null);
    } catch (_) {}
  }

  // ─────────── Last seen ───────────
  // Write the current moment to our own profile's last_seen_at.
  // Called on chat open and on every successful send — event-based
  // approach keeps writes cheap (5-20/day/user in practice).
  Future<void> _pingLastSeen() async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', _myId);
    } catch (_) {
      // Silent — last_seen is best-effort, never blocks user action
    }
  }

  // Fetch the other user's last_seen_at once on chat open
  Future<void> _loadOtherLastSeen() async {
    final otherId = widget.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('last_seen_at')
          .eq('id', otherId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final raw = row['last_seen_at'];
      if (raw == null) return;
      final ts = DateTime.tryParse(raw.toString());
      if (ts != null) setState(() => _otherLastSeen = ts.toUtc());
    } catch (_) {}
  }

  // Format timestamp WhatsApp-style.
  // Returns null if no usable timestamp (we'll hide the line in that case).
  String? _formatLastSeen(DateTime? tsUtc) {
    if (tsUtc == null) return null;
    final now = DateTime.now();
    final ts = tsUtc.toLocal();
    final diff = now.difference(ts);

    // Under a minute — treat as effectively online, but presence handles that.
    // If we're asked to format, it means presence is off, so just show "just now".
    if (diff.inSeconds < 60) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';

    // Same calendar day
    final sameDay = ts.year == now.year && ts.month == now.month && ts.day == now.day;
    String timeStr = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'last seen today at $timeStr';

    // Yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = ts.year == yesterday.year &&
        ts.month == yesterday.month &&
        ts.day == yesterday.day;
    if (isYesterday) return 'last seen yesterday at $timeStr';

    // Within last 7 days — show weekday name
    if (diff.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final dayName = weekdays[(ts.weekday - 1) % 7];
      return 'last seen $dayName at $timeStr';
    }

    // Older — show date (e.g. "15 Apr")
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'last seen ${ts.day} ${months[ts.month - 1]}';
  }

  // Header status resolver — priority:
  // typing > online > last_seen > job_title
  Widget _buildHeaderStatus() {
    if (_jobStatus == 'cancelled') {
      return const _HeaderStatusPill(
        key: ValueKey('job_cancelled'),
        text: 'Job cancelled',
        showDot: false,
      );
    }
    if (_otherIsTyping) {
      return const _HeaderStatusPill(
        key: ValueKey('typing'),
        text: 'typing...',
        showDot: false,
      );
    }
    if (_otherIsPresent) {
      return const _HeaderStatusPill(
        key: ValueKey('online'),
        text: 'online',
        showDot: true,
      );
    }
    final lastSeenStr = _formatLastSeen(_otherLastSeen);
    if (lastSeenStr != null) {
      return _HeaderStatusPill(
        key: const ValueKey('last_seen'),
        text: lastSeenStr,
        showDot: false,
      );
    }
    return Container(
      key: const ValueKey('job'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.7,
        ),
      ),
      child: Text(
        _otherUserLocation != null && _otherUserLocation!.isNotEmpty
            ? '📍 $_otherUserLocation'
            : widget.jobTitle,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _loadOtherUserLocation() async {
    final otherId = widget.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('location')
          .eq('id', otherId)
          .maybeSingle();
      if (!mounted) return;
      final loc = row?['location']?.toString().trim();
      if (loc != null && loc.isNotEmpty) {
        setState(() => _otherUserLocation = loc);
      }
    } catch (e) {
      debugPrint('Load chat partner location: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            final newMsg = payload.newRecord;
            if (newMsg['sender_id'] != _myId) {
              _markAsRead();
            }
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  // ─────────── Presence + typing channel ───────────
  // Supabase Realtime Broadcast = ephemeral messages (no DB writes)
  // Presence = list of who's subscribed; we just care "is the other user here"
  void _subscribePresence() {
    final channelName = 'presence:${widget.conversationId}';
    _presenceChannel = Supabase.instance.client.channel(
      channelName,
      opts: RealtimeChannelConfig(
        self: false, // don't receive our own broadcasts
        key: _myId,  // our presence key
      ),
    );

    // Handle "typing" broadcast events from the other user
    _presenceChannel!.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final fromId = payload['from'] as String?;
        if (fromId == null || fromId == _myId) return;
        if (!mounted) return;
        setState(() => _otherIsTyping = true);
        _otherTypingClearTimer?.cancel();
        _otherTypingClearTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _otherIsTyping = false);
        });
      },
    );

    // "Stopped typing" — clear immediately
    _presenceChannel!.onBroadcast(
      event: 'stopped_typing',
      callback: (payload) {
        final fromId = payload['from'] as String?;
        if (fromId == null || fromId == _myId) return;
        if (!mounted) return;
        _otherTypingClearTimer?.cancel();
        setState(() => _otherIsTyping = false);
      },
    );

    // Presence sync — who else is on this channel
    _presenceChannel!.onPresenceSync((_) {
      final state = _presenceChannel!.presenceState();
      // state is a list of SinglePresenceState with a presences list
      bool otherHere = false;
      for (final entry in state) {
        for (final p in entry.presences) {
          final id = (p.payload['user_id'] as String?) ?? '';
          if (id.isNotEmpty && id != _myId) {
            otherHere = true;
            break;
          }
        }
        if (otherHere) break;
      }
      if (mounted) setState(() => _otherIsPresent = otherHere);
    });

    _presenceChannel!.subscribe((status, err) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Announce our presence on this channel
        try {
          await _presenceChannel!.track({'user_id': _myId});
        } catch (_) {}
      }
    });
  }

  // Throttle: send "typing" every 2s while user is typing
  void _broadcastTyping() {
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!).inMilliseconds > 2000) {
      _lastTypingSent = now;
      _sendBroadcast('typing');
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      _sendBroadcast('stopped_typing');
      _lastTypingSent = null;
    });
  }

  Future<void> _sendBroadcast(String event) async {
    final channel = _presenceChannel;
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(
        event: event,
        payload: {'from': _myId},
      );
    } catch (_) {
      // swallow — broadcasts are best-effort
    }
  }

  Future<void> _markAsRead() async {
    try {
      final field = _isEmployer ? 'employer_unread_count' : 'worker_unread_count';
      await Supabase.instance.client
          .from('conversations')
          .update({field: 0})
          .eq('id', widget.conversationId);
      await Supabase.instance.client
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', _myId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();
    // Event-based last_seen ping: sending a message is activity.
    LastSeenPinger.ping();
    // Tell the other side we stopped typing — the send itself is the action
    _typingDebounce?.cancel();
    _lastTypingSent = null;
    _sendBroadcast('stopped_typing');
    final replyTo = _replyingTo;
    // Clear reply state immediately so UI snaps back
    if (replyTo != null) setState(() => _replyingTo = null);

    try {
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': text,
        'message_type': 'text',
        if (replyTo != null) 'reply_to_id': replyTo['id'],
      });
      _scrollToBottom();
      _pingLastSeen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
        );
        _messageController.text = text;
        if (replyTo != null) setState(() => _replyingTo = replyTo);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ─────────── Image attachment pipeline ───────────
  // 1. Pick → 2. Compress → 3. Upload to storage → 4. Insert message row with URL
  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isSending) return;

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,  // larger — the cropper will handle final size
      );
      if (picked == null) return;

      if (!mounted) return;

      // ─── Photo editor: crop + rotate ───
      // WhatsApp-style flow: cropper opens immediately after pick.
      // User can crop, rotate, choose aspect ratio, or tap Done to send as-is.
      // Cancelling the cropper aborts the whole send — no message inserted.
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Edit photo',
            toolbarColor: JobsyColors.background,
            toolbarWidgetColor: Colors.white,
            statusBarColor: JobsyColors.background,
            backgroundColor: JobsyColors.background,
            activeControlsWidgetColor: _primaryColor,
            cropFrameColor: _primaryColor,
            cropGridColor: Colors.white.withOpacity(0.3),
            dimmedLayerColor: Colors.black.withOpacity(0.6),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Edit photo',
            doneButtonTitle: 'Send',
            cancelButtonTitle: 'Cancel',
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );
      if (cropped == null) return; // user cancelled the editor

      if (!mounted) return;
      setState(() => _isSending = true);

      // Compress the cropped output for upload
      final compressed = await FlutterImageCompress.compressWithFile(
        cropped.path,
        quality: 80,
        minWidth: 1280,
        minHeight: 1280,
      );
      final bytes = compressed ?? await File(cropped.path).readAsBytes();

      // Path: {conversationId}/{timestamp}_{random}.jpg
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = cropped.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final fileName = '${timestamp}_${_myId.substring(0, 8)}.$ext';
      final storagePath = '${widget.conversationId}/$fileName';

      final storage = Supabase.instance.client.storage.from('chat-attachments');
      await storage.uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
          upsert: false,
        ),
      );

      // Create signed URL valid for 7 days (renewed on read elsewhere if needed)
      final signedUrl = await storage.createSignedUrl(storagePath, 60 * 60 * 24 * 7);

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': null,
        'message_type': 'image',
        'attachment_url': signedUrl,
        'attachment_meta': {
          'storage_path': storagePath,
          'size': bytes.length,
          'mime': ext == 'png' ? 'image/png' : 'image/jpeg',
        },
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _scrollToBottom();
      _pingLastSeen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ─────────── Voice note pipeline ───────────
  // Press-and-hold mic: start recording
  // Release: stop + send (unless _cancelArmed)
  // Drag left past threshold: cancel on release
  Future<void> _onVoiceTapStart(LongPressStartDetails details) async {
    if (_isSending || _isRecording) return;

    // Must have permission AND record must actually start
    HapticFeedback.selectionClick();
    final ok = await _voiceController.start();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Microphone permission required to record voice notes',
          ),
          backgroundColor: JobsyColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _isRecording = true;
      _recordingStartedAt = DateTime.now();
      _recordSlideOffset = 0;
      _recordSlideUpOffset = 0;
      _cancelArmed = false;
      _lockArmed = false;
      _isLocked = false;
    });
  }

  void _onVoiceTapMove(LongPressMoveUpdateDetails details) {
    if (!_isRecording || _isLocked) return;
    // Horizontal drag from start point; only negative (leftward) matters for cancel
    final dx = details.localOffsetFromOrigin.dx.clamp(-160.0, 0.0);
    // Vertical drag from start point; only negative (upward) matters for lock
    final dy = details.localOffsetFromOrigin.dy.clamp(-160.0, 0.0);

    // Thresholds: whichever axis is further past its threshold wins
    final cancelAmount = dx < 0 ? -dx : 0.0;  // 0..160
    final lockAmount = dy < 0 ? -dy : 0.0;    // 0..160

    // If both axes are armed (diagonal drag), the user's intent is ambiguous.
    // Pick whichever is further past its threshold. Lock wins ties since
    // it's the deliberate "advanced" gesture.
    final newCancelArmed = cancelAmount > 80 && cancelAmount >= lockAmount;
    final newLockArmed = lockAmount > 80 && lockAmount > cancelAmount;

    if (newCancelArmed != _cancelArmed || newLockArmed != _lockArmed) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _recordSlideOffset = dx;
      _recordSlideUpOffset = dy;
      _cancelArmed = newCancelArmed;
      _lockArmed = newLockArmed;
    });
  }

  Future<void> _onVoiceTapEnd(LongPressEndDetails details) async {
    if (!_isRecording || _isLocked) return;

    final wasCancelArmed = _cancelArmed;
    final wasLockArmed = _lockArmed;

    // Cancel takes priority
    if (wasCancelArmed) {
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _recordSlideOffset = 0;
        _recordSlideUpOffset = 0;
        _cancelArmed = false;
        _lockArmed = false;
      });
      await _voiceController.cancel();
      return;
    }

    // Lock: stay in recording mode, hands-free
    if (wasLockArmed) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isLocked = true;
        _recordSlideOffset = 0;
        _recordSlideUpOffset = 0;
        _cancelArmed = false;
        _lockArmed = false;
      });
      return;
    }

    // Release without cancel/lock → stop + send
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
      _recordSlideOffset = 0;
      _recordSlideUpOffset = 0;
      _cancelArmed = false;
      _lockArmed = false;
    });

    final result = await _voiceController.stop();
    if (result == null) {
      // Too short or failed — silently drop
      return;
    }
    await _uploadAndSendVoice(result.$1, result.$2);
  }

  // Locked-mode actions
  Future<void> _stopLockedRecording() async {
    if (!_isLocked) return;
    HapticFeedback.selectionClick();
    final result = await _voiceController.stop();
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
      _isLocked = false;
    });
    if (result == null) return;
    await _uploadAndSendVoice(result.$1, result.$2);
  }

  Future<void> _cancelLockedRecording() async {
    if (!_isLocked) return;
    HapticFeedback.selectionClick();
    await _voiceController.cancel();
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
      _isLocked = false;
    });
  }

  Future<void> _uploadAndSendVoice(String localPath, int seconds) async {
    if (!mounted) return;
    setState(() => _isSending = true);

    try {
      final file = File(localPath);
      final bytes = await file.readAsBytes();

      // Safety cap: 3 min @ 24 kbps ≈ 540 KB — but guard anyway
      if (bytes.length > 2 * 1024 * 1024) {
        throw Exception('Voice note too large');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_${timestamp}_${_myId.substring(0, 8)}.m4a';
      final storagePath = '${widget.conversationId}/$fileName';

      final storage = Supabase.instance.client.storage.from('chat-attachments');
      await storage.uploadBinary(
        storagePath,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'audio/m4a',
          upsert: false,
        ),
      );
      final signedUrl = await storage.createSignedUrl(storagePath, 60 * 60 * 24 * 7);

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': null,
        'message_type': 'voice',
        'attachment_url': signedUrl,
        'attachment_meta': {
          'storage_path': storagePath,
          'size': bytes.length,
          'mime': 'audio/m4a',
          'duration_seconds': seconds,
        },
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _scrollToBottom();
      _pingLastSeen();

      // Clean up temp file
      try { await file.delete(); } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ─────────── Document attachment pipeline ───────────
  // Picks a PDF/DOC/DOCX/TXT (≤ 2 MB), uploads, inserts 'file' message.
  Future<void> _pickAndSendDocument() async {
    if (_isSending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'txt'],
        withData: true, // load bytes for platforms where path is unreliable
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final fileName = picked.name;
      final ext = (picked.extension ?? '').toLowerCase();
      final size = picked.size;

      // Hard cap: 2 MB to protect the free tier
      const int maxBytes = 2 * 1024 * 1024;
      if (size > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max 2 MB.',
            ),
            backgroundColor: JobsyColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Prefer bytes (works everywhere); fall back to reading from path
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Could not read file contents');
      }

      if (!mounted) return;
      setState(() => _isSending = true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Sanitize filename for the storage path while keeping extension
      final safeBase = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath = '${widget.conversationId}/doc_${timestamp}_$safeBase';

      final contentType = _mimeForExtension(ext);

      final storage = Supabase.instance.client.storage.from('chat-attachments');
      await storage.uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: false,
        ),
      );
      final signedUrl = await storage.createSignedUrl(storagePath, 60 * 60 * 24 * 7);

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': null,
        'message_type': 'file',
        'attachment_url': signedUrl,
        'attachment_meta': {
          'storage_path': storagePath,
          'size': size,
          'mime': contentType,
          'filename': fileName,
          'ext': ext,
        },
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _scrollToBottom();
      _pingLastSeen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _mimeForExtension(String ext) {
    switch (ext) {
      case 'pdf':  return 'application/pdf';
      case 'doc':  return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':  return 'text/plain';
      default:     return 'application/octet-stream';
    }
  }

  // ─────────── Location attachment pipeline ───────────
  // Zero storage cost: just lat/lng + reverse-geocoded address in attachment_meta.
  Future<void> _shareCurrentLocation() async {
    if (_isSending) return;
    try {
      // 1. Service check
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location services are disabled. Turn them on and try again.'),
            backgroundColor: JobsyColors.error,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // 2. Permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission denied'),
            backgroundColor: JobsyColors.error,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isSending = true);

      // 3. Get position with a sensible timeout
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );

      // 4. Reverse-geocode (best effort — empty address is fine)
      String address = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').isNotEmpty) p.street!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
            if ((p.country ?? '').isNotEmpty) p.country!,
          ];
          address = parts.join(', ');
        }
      } catch (_) {
        // Reverse geocode can fail offline; proceed with just coords
      }

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': null,
        'message_type': 'location',
        'attachment_url': null,
        'attachment_meta': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'address': address,
        },
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _scrollToBottom();
      _pingLastSeen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ─────────── Contact attachment pipeline ───────────
  // Zero storage cost: name + phone stored in attachment_meta.
  // Uses native OS picker so we don't need READ_CONTACTS permission.
  Future<void> _pickAndSendContact() async {
    if (_isSending) return;
    try {
      final picker = FlutterNativeContactPicker();
      final contact = await picker.selectContact();
      if (contact == null) return; // user canceled

      final name = (contact.fullName ?? '').trim();
      final phones = (contact.phoneNumbers ?? <String>[]).where((p) => p.trim().isNotEmpty).toList();
      final phone = phones.isNotEmpty ? phones.first : '';

      if (name.isEmpty && phone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected contact has no name or phone'),
            backgroundColor: JobsyColors.error,
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isSending = true);

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': null,
        'message_type': 'contact',
        'attachment_url': null,
        'attachment_meta': {
          'name': name,
          'phone': phone,
        },
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _scrollToBottom();
      _pingLastSeen();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // Open a file URL (document) using the device's default app
  Future<void> _openFileUrl(String url, {String? ext, String? filename}) async {
    // PDFs → in-app viewer for a smoother experience (no "save file" prompt dance)
    if ((ext ?? '').toLowerCase() == 'pdf') {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            url: url,
            filename: filename ?? 'Document.pdf',
          ),
        ),
      );
      return;
    }
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No app available to open this file'),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  // Open location in device's default map app
  Future<void> _openLocationInMaps(double lat, double lng) async {
    // geo: is the Android-standard; iOS needs maps://
    final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final Uri fallback = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  // Open a phone number in the dialer
  Future<void> _dialPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  // ─── Worker: mark their side done ────────────────────────────────────────
  // ─── Helper: fire-and-forget notification insert ─────────────────────────
  Future<void> _insertNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    required String targetRole,
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'target_role': targetRole,
        'related_conversation_id': widget.conversationId,
        if (_jobId != null) 'related_job_id': _jobId,
        if (_applicationId != null) 'related_application_id': _applicationId,
      });
    } catch (e) {
      debugPrint('Notification insert failed: $e');
    }
  }

  Future<void> _markWorkerDone() async {
    if (_applicationId == null) return;
    if (!await _ensureProfileMode(needEmployer: false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JobsyColors.workerPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.check_circle_outline,
                  color: JobsyColors.workerPrimary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Complete Job?', style: TextStyle(fontSize: 17))),
          ],
        ),
        content: Text(
          'Let the employer know you\'ve finished "${widget.jobTitle}". They will review and confirm completion.',
          style: TextStyle(
              fontSize: 14, color: JobsyColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: JobsyColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Complete Job'),
            style: JobsyColors.workerFilledButtonStyle(radius: 10),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('job_applications')
          .update({'worker_completed': true}).eq('id', _applicationId!);

      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message':
            '🙋 Worker has marked "${widget.jobTitle}" as done and is awaiting your confirmation.',
      });

      // Notify employer in real-time
      if (widget.otherUserId != null) {
        await _insertNotification(
          userId: widget.otherUserId!,
          type: 'worker_done',
          title: 'Worker has finished the job!',
          body: 'The worker marked "${widget.jobTitle}" as done. Tap to confirm completion.',
          targetRole: AppConstants.userTypeEmployer,
        );
      }

      if (mounted) {
        setState(() => _workerCompleted = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: JobsyColors.workerOnAccent, size: 20),
              SizedBox(width: 8),
              Text('Marked as done — waiting for employer to confirm.',
                  style: TextStyle(color: JobsyColors.workerOnAccent)),
            ]),
            backgroundColor: JobsyColors.workerPrimary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted && _handleModeLockError(e)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _ensureProfileMode({required bool needEmployer}) async {
    final inEmployerMode = await RoleService.isEmployerMode();
    if (needEmployer && !inEmployerMode) {
      _offerModeSwitch(AppConstants.userTypeEmployer);
      return false;
    }
    if (!needEmployer && inEmployerMode) {
      _offerModeSwitch(AppConstants.userTypeWorker);
      return false;
    }
    return true;
  }

  bool _handleModeLockError(Object e) {
    if (e is! PostgrestException) return false;
    final msg = e.message.toLowerCase();
    if (msg.contains('switch to employer mode')) {
      _offerModeSwitch(AppConstants.userTypeEmployer);
      return true;
    }
    if (msg.contains('switch to worker mode')) {
      _offerModeSwitch(AppConstants.userTypeWorker);
      return true;
    }
    return false;
  }

  void _offerModeSwitch(String targetRole) {
    if (!mounted) return;
    final label = RoleService.roleLabel(targetRole);
    final accent = targetRole == AppConstants.userTypeEmployer
        ? JobsyColors.employerPrimary
        : JobsyColors.workerPrimary;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switch to $label mode to complete this action.'),
        backgroundColor: JobsyColors.surfaceElevated,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Switch',
          textColor: accent,
          onPressed: () {
            RoleService.confirmAndSwitch(
              context,
              targetRole: targetRole,
              initialTab: 0,
            );
          },
        ),
      ),
    );
  }

  // ─── Employer: confirm job complete ──────────────────────────────────────
  Future<void> _markJobComplete() async {
    if (_jobId == null) return;
    if (!await _ensureProfileMode(needEmployer: true)) return;

    if (!_workerCompleted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The worker must tap Complete Job first before you can confirm.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirm Job Complete?', style: TextStyle(fontSize: 17))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will mark "${widget.jobTitle}" as completed.',
                style: TextStyle(fontSize: 14, color: JobsyColors.textSecondary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The job will be removed from available listings and the worker will be notified.',
                      style: TextStyle(fontSize: 12, color: Colors.amber[800], height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: JobsyColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Complete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Update job status
      await Supabase.instance.client
          .from('jobs')
          .update({'status': 'completed'})
          .eq('id', _jobId!);

      // Also update all accepted/in_progress applications for this job (BUG-04 fix)
      await Supabase.instance.client
          .from('job_applications')
          .update({'status': 'completed'})
          .eq('job_id', _jobId!)
          .inFilter('status', ['accepted', 'in_progress']);

      // Send a system message
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'message': '✅ Job "${widget.jobTitle}" has been marked as completed. Thank you for your work!',
      });

      // Notify worker in real-time that the job is officially done
      if (widget.otherUserId != null) {
        await _insertNotification(
          userId: widget.otherUserId!,
          type: 'job_completed',
          title: 'Job Completed! 🎉',
          body: '"${widget.jobTitle}" has been confirmed complete. You can now rate the employer.',
          targetRole: AppConstants.userTypeWorker,
        );
      }

      if (mounted) {
        setState(() => _jobStatus = 'completed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: JobsyColors.surfaceLight, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Job marked as completed!')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        // Show rating dialog for employer immediately after completion
        if (widget.otherUserId != null && _applicationId != null) {
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => RatingDialog(
              jobTitle: widget.jobTitle,
              ratedUserId: widget.otherUserId!,
              ratedUserName: widget.otherUserName,
              jobId: _jobId!,
              applicationId: _applicationId!,
              conversationId: widget.conversationId,
              isRatingWorker: true,
            ),
          );
          await _refreshHasRated();
        }
      }
    } catch (e) {
      if (mounted && _handleModeLockError(e)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showOtherUserProfile() async {
    if (widget.otherUserId == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, avatar_url, location, bio, skills, experience_level, hourly_rate, phone')
          .eq('id', widget.otherUserId!)
          .maybeSingle();

      if (!mounted || profile == null) return;

      final name = profile['full_name'] ?? 'User';
      final avatarUrl = profile['avatar_url'];
      final location = profile['location'];
      final bio = profile['bio'];
      final skills = profile['skills'];
      final experience = profile['experience_level'];
      final rate = profile['hourly_rate'];
      final phone = profile['phone'];

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: JobsyColors.surfaceLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(color: JobsyColors.border, borderRadius: BorderRadius.circular(2)),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isEmployer
                          ? JobsyColors.employerCoverGradient
                          : JobsyColors.workerCoverGradient,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: JobsyColors.background.withOpacity(0.3),
                        backgroundImage: avatarUrl != null && avatarUrl.toString().isNotEmpty
                            ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null || avatarUrl.toString().isEmpty
                            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      if (location != null && location.toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on, color: Colors.white70, size: 16),
                            const SizedBox(width: 4),
                            Text(location.toString(), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (bio != null && bio.toString().isNotEmpty)
                        _pSection(Icons.info_outline, 'About', bio.toString()),
                      if (experience != null)
                        _pSection(Icons.star_outline, 'Experience', experience.toString().toUpperCase()),
                      if (rate != null)
                        _pSection(Icons.payments_outlined, 'Rate', 'P$rate/hr'),
                      if (phone != null && phone.toString().isNotEmpty)
                        _pSection(Icons.phone_outlined, 'Phone', phone.toString()),
                      if (skills != null && skills is List && (skills as List).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: (skills as List).map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(s.toString(), style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w500)),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Widget _pSection(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JobsyColors.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JobsyColors.surfaceLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: JobsyColors.textTertiary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 15, color: JobsyColors.textPrimary)),
              ],
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.otherUserAvatar != null && widget.otherUserAvatar!.isNotEmpty;

    return PopScope(
      canPop: !_showEmojiPicker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showEmojiPicker) {
          setState(() => _showEmojiPicker = false);
        }
      },
      child: Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: ClipRect(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isEmployer
                    ? JobsyColors.employerCoverGradient
                    : JobsyColors.workerCoverGradient,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.18),
                          Colors.white.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
                    child: Row(
                      children: [
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        // Profile photo with tap
                        GestureDetector(
                          onTap: _showOtherUserProfile,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white.withOpacity(0.15),
                              backgroundImage: hasAvatar ? NetworkImage(widget.otherUserAvatar!) : null,
                              child: !hasAvatar
                                  ? Text(
                                      widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Name and job title
                        Expanded(
                          child: GestureDetector(
                      onTap: _showOtherUserProfile,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.otherUserName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.2,
                                shadows: [
                                  Shadow(
                                    color: Color(0x33000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, anim) =>
                                FadeTransition(opacity: anim, child: child),
                            child: _buildHeaderStatus(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  // Employer: Complete Job button (requires worker confirmation first)
                  if (_isEmployer &&
                      (_jobStatus == 'active' || _jobStatus == 'in_progress'))
                    Tooltip(
                      message: _workerCompleted
                          ? 'Worker confirmed — tap to finalize the job'
                          : 'Waiting for the worker to tap Complete Job',
                      preferBelow: false,
                      child: Opacity(
                        opacity: _workerCompleted ? 1.0 : 0.55,
                        child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _workerCompleted
                                ? [Colors.green[700]!, Colors.green[500]!]
                                : [Colors.grey[700]!, Colors.grey[500]!],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (_workerCompleted ? Colors.green : Colors.grey)
                                  .withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _workerCompleted ? _markJobComplete : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'The worker must tap Complete Job before you can confirm.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _workerCompleted
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    color: JobsyColors.surfaceLight,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Complete Job',
                                    style: const TextStyle(
                                      color: JobsyColors.surfaceLight,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),

                  // Worker: Complete Job button (active or in_progress, not yet marked)
                  if (!_isEmployer &&
                      (_jobStatus == 'active' || _jobStatus == 'in_progress') &&
                      !_workerCompleted)
                    Tooltip(
                      message: 'Tap to confirm you\'ve finished the work',
                      preferBelow: false,
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: JobsyColors.workerPrimary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: JobsyColors.workerPrimary.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _markWorkerDone,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: JobsyColors.workerOnAccent, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Complete Job',
                                      style: TextStyle(
                                        color: JobsyColors.workerOnAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Worker: awaiting employer confirmation
                  if (!_isEmployer &&
                      _workerCompleted &&
                      _jobStatus != 'completed')
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange[600],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top,
                              color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Awaiting',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (_isEmployer && _jobStatus == 'completed')
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: JobsyColors.surfaceLight, size: 14),
                          SizedBox(width: 4),
                          Text('Done', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Banner: worker rating prompt when job is complete and not yet rated
          if (!_isEmployer &&
              _jobStatus == 'completed' &&
              !_hasRated &&
              widget.otherUserId != null &&
              _applicationId != null)
            Material(
              color: JobsyColors.workerPrimary.withOpacity(0.12),
              child: InkWell(
                onTap: () async {
                  await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => RatingDialog(
                      jobTitle: widget.jobTitle,
                      ratedUserId: widget.otherUserId!,
                      ratedUserName: widget.otherUserName,
                      jobId: _jobId!,
                      applicationId: _applicationId!,
                      conversationId: widget.conversationId,
                      isRatingWorker: false,
                    ),
                  );
                  await _refreshHasRated();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.star_rounded,
                          color: JobsyColors.workerPrimary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Job complete! Tap to rate ${widget.otherUserName}.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: JobsyColors.workerPrimary,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: JobsyColors.workerPrimary, size: 18),
                    ],
                  ),
                ),
              ),
            ),

          // Banner: employer notification that worker has marked done
          if (_isEmployer &&
              _workerCompleted &&
              (_jobStatus == 'active' || _jobStatus == 'in_progress'))
            Material(
              color: Colors.green.withOpacity(0.10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Worker has marked this job as done. Tap "Confirm Done" to complete it.',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Messages list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('conversation_id', widget.conversationId)
                  .order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: JobsyColors.textTertiary),
                        const SizedBox(height: 8),
                        Text('Error loading messages', style: TextStyle(color: JobsyColors.textSecondary)),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: _primaryColor));
                }

                final rawMessages = snapshot.data!;
                // Filter out messages the current user has "deleted for me"
                final messages = rawMessages.where((m) {
                  final hidden = (m['hidden_for'] as List?)?.cast<dynamic>() ?? const [];
                  return !hidden.contains(_myId);
                }).toList();
                // Cache for reply-preview lookups (read by _buildBubble)
                _currentMessages = messages;

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: JobsyColors.border),
                          const SizedBox(height: 16),
                          Text('No messages yet',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: JobsyColors.textTertiary)),
                          const SizedBox(height: 8),
                          Text('Send a message to start the conversation about "${widget.jobTitle}"',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: JobsyColors.textTertiary)),
                        ],
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _myId;
                    final showDate = index == 0 ||
                        _isDifferentDay(messages[index - 1]['created_at'], msg['created_at']);
                    return Column(
                      children: [
                        if (showDate) _buildDateChip(msg['created_at']),
                        _buildBubble(msg, isMe),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Reply banner — shown above composer when replying
          if (_replyingTo != null) _buildReplyingToBanner(),

          // Locked recording mode — replaces the normal composer entirely
          if (_isLocked)
            _buildLockedRecordingBar()
          else
            // WhatsApp-style composer (with optional recording overlay on top)
            Stack(
              clipBehavior: Clip.none,
              children: [
                _buildComposer(),
                if (_isRecording && _recordingStartedAt != null)
                  Positioned(
                    left: 0,
                    // Reserve room on the right so the mic button stays visible & interactive
                    right: 70,
                    top: 6,
                    child: IgnorePointer(
                      child: RecordingOverlay(
                        startedAt: _recordingStartedAt!,
                        slideOffset: _recordSlideOffset,
                        cancelArmed: _cancelArmed,
                      ),
                    ),
                  ),
                // Lock hint: small floating chip ABOVE the mic button, visible
                // while recording. Slides up as user drags up; pulses when armed.
                if (_isRecording && _recordingStartedAt != null)
                  Positioned(
                    right: 22,
                    top: _lockArmed
                        ? -80
                        : -40 + (_recordSlideUpOffset * 0.4).clamp(-40.0, 0.0),
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _lockArmed
                              ? _primaryColor
                              : JobsyColors.surfaceElevated,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_lockArmed ? _primaryColor : Colors.black)
                                  .withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _lockArmed
                                  ? Icons.lock_rounded
                                  : Icons.lock_outline_rounded,
                              size: 18,
                              color: _lockArmed
                                  ? Colors.white
                                  : JobsyColors.textSecondary,
                            ),
                            const SizedBox(height: 2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 14,
                              color: (_lockArmed
                                      ? Colors.white
                                      : JobsyColors.textSecondary)
                                  .withOpacity(0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),

          // Emoji picker panel (shown below composer)
          Offstage(
            offstage: !_showEmojiPicker,
            child: SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _messageController,
                onBackspacePressed: () {
                  // Remove last emoji/character from text field
                },
                config: Config(
                  height: 280,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: const EmojiViewConfig(
                    emojiSizeMax: 28,
                    backgroundColor: JobsyColors.surfaceLight,
                    columns: 8,
                    verticalSpacing: 0,
                    horizontalSpacing: 0,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: JobsyColors.surfaceLight,
                    indicatorColor: _primaryColor,
                    iconColor: JobsyColors.textTertiary,
                    iconColorSelected: _primaryColor,
                    backspaceColor: _primaryColor,
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    backgroundColor: JobsyColors.surfaceLight,
                    buttonColor: _primaryColor,
                    buttonIconColor: Colors.white,
                  ),
                  searchViewConfig: const SearchViewConfig(
                    backgroundColor: JobsyColors.surfaceLight,
                    hintText: 'Search emoji',
                  ),
                  skinToneConfig: const SkinToneConfig(),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ───────────────── WhatsApp-style composer ─────────────────
  // Full-width bar shown when user has locked the recording.
  // Replaces the normal composer. Recording continues hands-free.
  Widget _buildLockedRecordingBar() {
    return Container(
      color: JobsyColors.background,
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        6 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Row(
        children: [
          // Cancel button — discards the recording
          Material(
            color: JobsyColors.surfaceElevated,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _cancelLockedRecording,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: JobsyColors.error,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Timer + pulsing red dot — mirrors the RecordingOverlay appearance
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _PulsingDot(),
                  const SizedBox(width: 10),
                  if (_recordingStartedAt != null)
                    _LockedTimer(startedAt: _recordingStartedAt!),
                  const Spacer(),
                  const Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: JobsyColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Locked',
                    style: TextStyle(
                      fontSize: 12,
                      color: JobsyColors.textTertiary,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Stop + send button — prominent, primary color
          Material(
            color: _primaryColor,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: _primaryColor.withOpacity(0.5),
            child: InkWell(
              onTap: _stopLockedRecording,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 6,
        bottom: _showEmojiPicker ? 6 : MediaQuery.of(context).padding.bottom + 6,
      ),
      decoration: BoxDecoration(
        color: JobsyColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Left: pill holding emoji + textfield + attach + camera
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 140, minHeight: 44),
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Emoji toggle
                  _composerIconButton(
                    icon: _showEmojiPicker
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                    onTap: _toggleEmojiPicker,
                  ),
                  // Text field (flexible)
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        fontSize: 15.5,
                        color: JobsyColors.textPrimary,
                        height: 1.35,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(
                          color: JobsyColors.textTertiary,
                          fontSize: 15.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                      ),
                      onTap: () {
                        if (_showEmojiPicker) {
                          setState(() => _showEmojiPicker = false);
                        }
                      },
                    ),
                  ),
                  // Attachment
                  _composerIconButton(
                    icon: Icons.attach_file_rounded,
                    onTap: _showAttachmentSheet,
                    iconRotation: 0.45, // gentle paperclip angle
                  ),
                  // Camera (only when empty, like WhatsApp)
                  if (!_hasText)
                    _composerIconButton(
                      icon: Icons.photo_camera_outlined,
                      onTap: _handleCameraQuickShot,
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Right: animated mic↔send button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: _hasText || _isSending
                ? Material(
                    key: const ValueKey('send'),
                    color: _primaryColor,
                    shape: const CircleBorder(),
                    elevation: 2,
                    shadowColor: _primaryColor.withOpacity(0.5),
                    child: InkWell(
                      onTap: _isSending ? null : _sendMessage,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  )
                : GestureDetector(
                    key: const ValueKey('mic'),
                    onLongPressStart: _onVoiceTapStart,
                    onLongPressMoveUpdate: _onVoiceTapMove,
                    onLongPressEnd: _onVoiceTapEnd,
                    onLongPressCancel: () async {
                      // If locked, do NOT cancel — user intentionally moved away.
                      if (_isLocked) return;
                      if (_isRecording) {
                        await _voiceController.cancel();
                        if (mounted) {
                          setState(() {
                            _isRecording = false;
                            _recordingStartedAt = null;
                            _recordSlideOffset = 0;
                            _recordSlideUpOffset = 0;
                            _cancelArmed = false;
                            _lockArmed = false;
                          });
                        }
                      }
                    },
                    onTap: () {
                      // Tap (not long-press) → gentle hint
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hold to record, release to send'),
                          duration: Duration(seconds: 2),
                          backgroundColor: JobsyColors.surfaceElevated,
                        ),
                      );
                    },
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 150),
                      scale: _isRecording ? 1.3 : 1.0,
                      child: Material(
                        color: _isRecording
                            ? JobsyColors.error
                            : _primaryColor,
                        shape: const CircleBorder(),
                        elevation: _isRecording ? 6 : 2,
                        shadowColor: (_isRecording
                                ? JobsyColors.error
                                : _primaryColor)
                            .withOpacity(0.5),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.mic_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _composerIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double iconRotation = 0,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Transform.rotate(
          angle: iconRotation,
          child: Icon(
            icon,
            color: JobsyColors.textTertiary,
            size: 24,
          ),
        ),
      ),
    );
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      // Closing panel → open keyboard
      setState(() => _showEmojiPicker = false);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      // Opening panel → hide keyboard first to avoid jumpy layout
      FocusScope.of(context).unfocus();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _showEmojiPicker = true);
      });
    }
  }

  void _showAttachmentSheet() {
    FocusScope.of(context).unfocus();
    if (_showEmojiPicker) setState(() => _showEmojiPicker = false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: JobsyColors.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 12,
            bottom: MediaQuery.of(ctx).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JobsyColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  runSpacing: 20,
                  children: [
                    _attachmentOption(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Document',
                      color: const Color(0xFF7F66FF),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendDocument();
                      },
                    ),
                    _attachmentOption(
                      icon: Icons.photo_camera_rounded,
                      label: 'Camera',
                      color: const Color(0xFFFF2E74),
                      onTap: () {
                        Navigator.pop(ctx);
                        _handleCameraQuickShot();
                      },
                    ),
                    _attachmentOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: const Color(0xFFC341F0),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage(ImageSource.gallery);
                      },
                    ),
                    _attachmentOption(
                      icon: Icons.location_on_rounded,
                      label: 'Location',
                      color: const Color(0xFF19C37D),
                      onTap: () {
                        Navigator.pop(ctx);
                        _shareCurrentLocation();
                      },
                    ),
                    _attachmentOption(
                      icon: Icons.person_rounded,
                      label: 'Contact',
                      color: JobsyColors.employerPrimary,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendContact();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 72,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: JobsyColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCameraQuickShot() {
    _pickAndSendImage(ImageSource.camera);
  }

  void _showNotImplementedSnack(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon'),
        duration: const Duration(seconds: 2),
        backgroundColor: JobsyColors.surfaceElevated,
      ),
    );
  }

  void _showBubbleMenu(Map<String, dynamic> msg, bool isMe) {
    final messageText = msg['message'] ?? '';
    final messageType = msg['message_type'] ?? 'text';
    final isDeleted = msg['deleted_at'] != null;
    // Tombstoned messages get no menu
    if (isDeleted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: JobsyColors.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 12,
            bottom: MediaQuery.of(ctx).padding.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JobsyColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              // Reply
              ListTile(
                leading: Icon(Icons.reply_rounded, color: _primaryColor),
                title: const Text(
                  'Reply',
                  style: TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyingTo = msg);
                  // Pull focus to composer
                  Future.delayed(const Duration(milliseconds: 80), () {
                    if (mounted) _focusNode.requestFocus();
                  });
                },
              ),
              // Copy (only for text messages)
              if (messageType == 'text' && messageText.toString().isNotEmpty)
                ListTile(
                  leading: Icon(Icons.copy_rounded, color: _primaryColor),
                  title: const Text(
                    'Copy',
                    style: TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: messageText));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 2),
                        backgroundColor: JobsyColors.surfaceElevated,
                      ),
                    );
                  },
                ),
              // Delete for me (always available)
              ListTile(
                leading: const Icon(
                  Icons.visibility_off_rounded,
                  color: JobsyColors.textSecondary,
                ),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                ),
                subtitle: const Text(
                  'Hide this message only on your device',
                  style: TextStyle(color: JobsyColors.textTertiary, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _deleteForMe(msg);
                },
              ),
              // Delete for everyone (only for your own messages)
              if (isMe)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_rounded,
                    color: JobsyColors.error,
                  ),
                  title: const Text(
                    'Delete for everyone',
                    style: TextStyle(color: JobsyColors.error, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Remove this message for all participants',
                    style: TextStyle(color: JobsyColors.textTertiary, fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _confirmDeleteForEveryone(msg);
                  },
                ),
              // Message info (only for your own, non-text is fine too)
              if (isMe)
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: _primaryColor),
                  title: const Text(
                    'Message info',
                    style: TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                  ),
                  subtitle: Text(
                    msg['is_read'] == true ? 'Read' : 'Delivered',
                    style: const TextStyle(
                      color: JobsyColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─────────── Delete actions ───────────
  Future<void> _deleteForMe(Map<String, dynamic> msg) async {
    try {
      // Append current user ID to hidden_for array (idempotent in Postgres using array_append inside a conditional)
      // We fetch existing, append, and update. Simpler than RPC given small row count.
      final existing = (msg['hidden_for'] as List?)?.cast<String>() ?? const [];
      if (existing.contains(_myId)) return; // already hidden
      final updated = [...existing, _myId];
      await Supabase.instance.client
          .from('messages')
          .update({'hidden_for': updated})
          .eq('id', msg['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteForEveryone(Map<String, dynamic> msg) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [JobsyColors.surfaceLight, JobsyColors.surface],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: JobsyColors.error.withOpacity(0.3),
              width: 0.7,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: JobsyColors.error.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: JobsyColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Delete for everyone?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'This message will be removed for all participants. This cannot be undone.',
                style: TextStyle(
                  fontSize: 13,
                  color: JobsyColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: JobsyColors.border.withOpacity(0.6),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: JobsyColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JobsyColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('messages').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        // Wipe content so even a stray client doesn't show it
        'message': null,
        'attachment_url': null,
      }).eq('id', msg['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isMe) {
    final time = DateTime.tryParse(msg['created_at'] ?? '');
    final timeStr = time != null
        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
        : '';
    final messageText = msg['message'] ?? '';
    final isRead = msg['is_read'] == true;
    final messageType = msg['message_type'] ?? 'text';
    final attachmentUrl = msg['attachment_url'] as String?;
    final bool isDeleted = msg['deleted_at'] != null;
    final String? replyToId = msg['reply_to_id'] as String?;

    // Short-circuit: tombstoned messages get a minimal "deleted" bubble
    if (isDeleted) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: EdgeInsets.only(
            top: 2,
            bottom: 2,
            left: isMe ? 56 : 8,
            right: isMe ? 8 : 56,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: JobsyColors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 14),
            ),
            border: Border.all(
              color: JobsyColors.border.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                size: 14,
                color: JobsyColors.textTertiary.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isMe ? 'You deleted this message' : 'This message was deleted',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    color: JobsyColors.textTertiary,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: JobsyColors.textTertiary.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Outgoing: primary color bubble, white text
    // Incoming: elevated dark surface, primary text
    final bubbleColor = isMe ? _primaryColor : JobsyColors.surfaceElevated;
    final textColor = isMe ? Colors.white : JobsyColors.textPrimary;
    final metaColor = isMe ? Colors.white.withOpacity(0.75) : JobsyColors.textTertiary;
    // WhatsApp double-check: grey when delivered, bright on read
    final checkColor = isMe
        ? (isRead ? const Color(0xFF66E0FF) : Colors.white.withOpacity(0.7))
        : JobsyColors.textTertiary;

    // Inline meta (time + optional checks) that sits at bottom-right of the last text line
    final metaRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 10.5,
            color: metaColor,
            letterSpacing: 0.1,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 3),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: checkColor,
          ),
        ],
      ],
    );

    // Image bubble: render the image with meta overlaid bottom-right on a dark scrim
    final bool isImage = messageType == 'image' && attachmentUrl != null;
    // Voice bubble: render playback widget with waveform
    final bool isVoice = messageType == 'voice' && attachmentUrl != null;
    final int voiceDuration = isVoice
        ? ((msg['attachment_meta'] is Map)
            ? ((msg['attachment_meta']['duration_seconds'] as num?)?.toInt() ?? 0)
            : 0)
        : 0;
    // File, location, contact — all use attachment_meta
    final Map<String, dynamic> meta = (msg['attachment_meta'] is Map)
        ? Map<String, dynamic>.from(msg['attachment_meta'] as Map)
        : const <String, dynamic>{};
    final bool isFile = messageType == 'file' && attachmentUrl != null;
    final bool isLocation = messageType == 'location';
    final bool isContact = messageType == 'contact';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showBubbleMenu(msg, isMe),
        onTap: isImage
            ? () => _showImageFullscreen(attachmentUrl)
            : (isFile
                ? () => _openFileUrl(
                      attachmentUrl,
                      ext: meta['ext'] as String?,
                      filename: meta['filename'] as String?,
                    )
                : (isLocation
                    ? () => _openLocationInMaps(
                          (meta['lat'] as num?)?.toDouble() ?? 0,
                          (meta['lng'] as num?)?.toDouble() ?? 0,
                        )
                    : (isContact
                        ? () => _dialPhone((meta['phone'] as String?) ?? '')
                        : null))),
        child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 56 : 8,
          right: isMe ? 8 : 56,
        ),
        // Image bubbles get a tiny 3px padding (image hugs corners)
        // Voice bubbles get a slightly roomier padding
        // Text bubbles get normal padding
        padding: isImage
            ? const EdgeInsets.all(3)
            : (isVoice
                ? const EdgeInsets.fromLTRB(10, 8, 10, 6)
                : const EdgeInsets.fromLTRB(10, 6, 10, 6)),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: () {
          final Widget contentBody = isImage
            ? _buildImageContent(attachmentUrl, metaRow, isMe)
            : (isVoice
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VoiceMessageBubble(
                        url: attachmentUrl,
                        durationSeconds: voiceDuration,
                        isMe: isMe,
                        accentColor: _primaryColor,
                      ),
                      const SizedBox(height: 2),
                      metaRow,
                    ],
                  )
                : (isFile
                    ? _buildFileContent(
                        meta: meta,
                        isMe: isMe,
                        metaRow: metaRow,
                      )
                    : (isLocation
                        ? _buildLocationContent(
                            meta: meta,
                            isMe: isMe,
                            metaRow: metaRow,
                          )
                        : (isContact
                            ? _buildContactContent(
                                meta: meta,
                                isMe: isMe,
                                metaRow: metaRow,
                              )
                            : Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 2, bottom: 2),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14.5,
                          color: textColor,
                          height: 1.32,
                          letterSpacing: 0.1,
                        ),
                        children: [
                          TextSpan(text: messageText),
                          // Invisible spacer that reserves space for the meta row
                          // so wrap logic accounts for its width.
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: Opacity(
                              opacity: 0,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: metaRow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: metaRow,
                  ),
                ],
              )))));

          if (replyToId == null) return contentBody;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildReplyPreviewInBubble(replyToId, isMe),
              const SizedBox(height: 4),
              contentBody,
            ],
          );
        }(),
      ),
      ),
    );
  }

  // Reply banner shown above the composer while composing a reply.
  // Tap the X to cancel the reply.
  Widget _buildReplyingToBanner() {
    final msg = _replyingTo!;
    final origSenderIsMe = msg['sender_id'] == _myId;
    final senderLabel = origSenderIsMe ? 'You' : widget.otherUserName;
    final ot = msg['message_type'] ?? 'text';
    String previewText;
    if (ot == 'image') {
      previewText = '📷 Photo';
    } else if (ot == 'voice') {
      previewText = '🎤 Voice message';
    } else if (ot == 'file') {
      final m = (msg['attachment_meta'] is Map) ? msg['attachment_meta'] as Map : const {};
      final fn = (m['filename'] as String?) ?? 'Document';
      previewText = '📎 $fn';
    } else if (ot == 'location') {
      previewText = '📍 Location';
    } else if (ot == 'contact') {
      final m = (msg['attachment_meta'] is Map) ? msg['attachment_meta'] as Map : const {};
      final n = (m['name'] as String?) ?? 'Contact';
      previewText = '👤 $n';
    } else {
      previewText = (msg['message'] ?? '').toString();
      if (previewText.isEmpty) previewText = '(empty message)';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: JobsyColors.background,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: _primaryColor, width: 3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.reply_rounded, size: 16, color: _primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Replying to $senderLabel',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _primaryColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: JobsyColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: JobsyColors.textTertiary,
                size: 20,
              ),
              onPressed: () => setState(() => _replyingTo = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // In-bubble reply preview. Looks up the replied-to message from the current list;
  // if not present, renders a minimal "Original message unavailable" fallback.
  Widget _buildReplyPreviewInBubble(String replyToId, bool isMe) {
    Map<String, dynamic>? original;
    for (final m in _currentMessages) {
      if (m['id'] == replyToId) { original = m; break; }
    }

    String senderLabel;
    String previewText;
    if (original == null) {
      senderLabel = 'Message';
      previewText = 'Original message unavailable';
    } else {
      final origSenderIsMe = original['sender_id'] == _myId;
      senderLabel = origSenderIsMe ? 'You' : widget.otherUserName;
      final ot = original['message_type'] ?? 'text';
      if (ot == 'image') {
        previewText = '📷 Photo';
      } else if (ot == 'voice') {
        previewText = '🎤 Voice message';
      } else if (ot == 'file') {
        final m = (original['attachment_meta'] is Map) ? original['attachment_meta'] as Map : const {};
        final fn = (m['filename'] as String?) ?? 'Document';
        previewText = '📎 $fn';
      } else if (ot == 'location') {
        previewText = '📍 Location';
      } else if (ot == 'contact') {
        final m = (original['attachment_meta'] is Map) ? original['attachment_meta'] as Map : const {};
        final n = (m['name'] as String?) ?? 'Contact';
        previewText = '👤 $n';
      } else {
        previewText = (original['message'] ?? '').toString();
        if (previewText.isEmpty) previewText = '(empty message)';
      }
    }

    final Color accent = isMe ? Colors.white : _primaryColor;
    final Color fg = isMe ? Colors.white.withOpacity(0.95) : JobsyColors.textPrimary;
    final Color bg = isMe
        ? Colors.white.withOpacity(0.15)
        : _primaryColor.withOpacity(0.1);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            previewText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: fg.withOpacity(0.8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // Renders image content with meta overlaid on a dark scrim (WhatsApp style)
  Widget _buildImageContent(String url, Widget metaRow, bool isMe) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 260,
              minWidth: 180,
              maxHeight: 340,
              minHeight: 140,
            ),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (ctx, _) => Container(
                width: 220,
                height: 220,
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white.withOpacity(0.7),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              errorWidget: (ctx, _, __) => Container(
                width: 220,
                height: 180,
                color: Colors.black.withOpacity(0.4),
                child: const Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          // Meta chip with dark scrim at bottom-right
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(100),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: IconTheme.merge(
                  data: const IconThemeData(color: Colors.white),
                  child: metaRow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── File (document) bubble ───────────
  Widget _buildFileContent({
    required Map<String, dynamic> meta,
    required bool isMe,
    required Widget metaRow,
  }) {
    final String filename = (meta['filename'] as String?) ?? 'Document';
    final int size = (meta['size'] as num?)?.toInt() ?? 0;
    final String ext = ((meta['ext'] as String?) ?? '').toLowerCase();
    final String sizeLabel = _formatFileSize(size);

    final Color fg = isMe ? Colors.white : JobsyColors.textPrimary;
    final Color subtle = isMe ? Colors.white.withOpacity(0.75) : JobsyColors.textTertiary;
    final Color iconBg = isMe
        ? Colors.white.withOpacity(0.18)
        : _primaryColor.withOpacity(0.15);

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    _fileIconFor(ext),
                    color: fg,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ext.toUpperCase().isEmpty ? 'FILE' : ext.toUpperCase()}  ·  $sizeLabel',
                      style: TextStyle(
                        fontSize: 11,
                        color: subtle,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          metaRow,
        ],
      ),
    );
  }

  IconData _fileIconFor(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx': return Icons.description_rounded;
      case 'txt': return Icons.article_outlined;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  // ─────────── Location bubble ───────────
  Widget _buildLocationContent({
    required Map<String, dynamic> meta,
    required bool isMe,
    required Widget metaRow,
  }) {
    final String address = (meta['address'] as String?) ?? '';
    final double lat = (meta['lat'] as num?)?.toDouble() ?? 0;
    final double lng = (meta['lng'] as num?)?.toDouble() ?? 0;

    final Color fg = isMe ? Colors.white : JobsyColors.textPrimary;
    final Color subtle = isMe ? Colors.white.withOpacity(0.8) : JobsyColors.textTertiary;
    final Color accentBg = isMe
        ? Colors.white.withOpacity(0.18)
        : const Color(0xFF19C37D).withOpacity(0.15);
    final Color accent = isMe ? Colors.white : const Color(0xFF19C37D);

    final String coordsLabel =
        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Icons.location_on_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address.isNotEmpty ? address : coordsLabel,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtle,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 11,
                          color: subtle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tap to open in Maps',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: subtle,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          metaRow,
        ],
      ),
    );
  }

  // ─────────── Contact bubble ───────────
  Widget _buildContactContent({
    required Map<String, dynamic> meta,
    required bool isMe,
    required Widget metaRow,
  }) {
    final String name = (meta['name'] as String?) ?? 'Contact';
    final String phone = (meta['phone'] as String?) ?? '';

    final Color fg = isMe ? Colors.white : JobsyColors.textPrimary;
    final Color subtle = isMe ? Colors.white.withOpacity(0.8) : JobsyColors.textTertiary;
    final Color accentBg = isMe
        ? Colors.white.withOpacity(0.18)
        : _primaryColor.withOpacity(0.15);

    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Circle avatar with initial
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentBg,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtle,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.call_rounded,
                          size: 11,
                          color: subtle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          phone.isNotEmpty ? 'Tap to call' : 'No number',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: subtle,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          metaRow,
        ],
      ),
    );
  }

  // Tap an image to open fullscreen with pinch-to-zoom
  void _showImageFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
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
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Material(
                    color: Colors.black.withOpacity(0.5),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(String? timestamp) {
    if (timestamp == null) return const SizedBox.shrink();
    final date = DateTime.tryParse(timestamp);
    if (date == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final diff = now.difference(date);
    String label;
    if (diff.inDays == 0) {
      label = 'Today';
    } else if (diff.inDays == 1) {
      label = 'Yesterday';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: JobsyColors.border?.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(fontSize: 12, color: JobsyColors.textSecondary)),
        ),
      ),
    );
  }

  bool _isDifferentDay(String? a, String? b) {
    if (a == null || b == null) return true;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return true;
    return da.year != db.year || da.month != db.month || da.day != db.day;
  }
}

// Small pill used in the chat header to show live status: "typing..." or "online".
// Matches the visual language of the jobTitle pill (same radius, white translucent bg).
class _HeaderStatusPill extends StatelessWidget {
  final String text;
  final bool showDot;

  const _HeaderStatusPill({
    super.key,
    required this.text,
    required this.showDot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981), // emerald green
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// Pulsing red dot used in the locked recording bar. Self-contained stateful
// widget so the parent doesn't need a ticker.
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withOpacity(0.6),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// Mono-spaced timer that refreshes every 200ms while locked.
class _LockedTimer extends StatefulWidget {
  final DateTime startedAt;
  const _LockedTimer({required this.startedAt});

  @override
  State<_LockedTimer> createState() => _LockedTimerState();
}

class _LockedTimerState extends State<_LockedTimer> {
  Timer? _t;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(widget.startedAt));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = _elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      '$mm:$ss',
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: JobsyColors.textPrimary,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
