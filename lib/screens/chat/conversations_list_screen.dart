import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/colors.dart';
import '../../config/page_transitions.dart';
import '../../services/last_seen_pinger.dart';
import '../../utils/profile_rating.dart';
import 'chat_screen.dart';

class ConversationsListScreen extends StatefulWidget {
  final bool isEmployer;

  const ConversationsListScreen({super.key, required this.isEmployer});

  @override
  State<ConversationsListScreen> createState() =>
      _ConversationsListScreenState();
}

class _ConversationsListScreenState extends State<ConversationsListScreen> {
  Color get _primaryColor =>
      widget.isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  String get _myId => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    // Event-based last_seen ping: opening the chat list counts as "active".
    LastSeenPinger.ping();
  }

  @override
  Widget build(BuildContext context) {
    if (_myId.isEmpty) {
      return const Center(child: Text('Please log in to view messages'));
    }

    final filterColumn = widget.isEmployer ? 'employer_id' : 'worker_id';

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('conversations')
                .stream(primaryKey: ['id'])
                .eq(filterColumn, _myId)
                .order('updated_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: JobsyColors.textTertiary),
                        const SizedBox(height: 12),
                        Text('Error loading conversations',
                            style: TextStyle(color: JobsyColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: _primaryColor),
                );
              }

              final conversations = snapshot.data!
                  .where((c) => c['inbox_visible'] == true)
                  .toList();

              if (conversations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 80, color: JobsyColors.border),
                      const SizedBox(height: 16),
                      Text('No conversations yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: JobsyColors.textTertiary)),
                      const SizedBox(height: 8),
                      Text(
                        widget.isEmployer
                            ? 'Accept an application to start chatting'
                            : 'Get accepted to start chatting with employers',
                        style: TextStyle(fontSize: 14, color: JobsyColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  return AnimatedListItem(
                    index: index,
                    child: _ConversationCard(
                      conversation: conversations[index],
                      isEmployer: widget.isEmployer,
                      myId: _myId,
                      primaryColor: _primaryColor,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Individual conversation card ─────────────────────

class _ConversationCard extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final bool isEmployer;
  final String myId;
  final Color primaryColor;

  const _ConversationCard({
    required this.conversation,
    required this.isEmployer,
    required this.myId,
    required this.primaryColor,
  });

  @override
  State<_ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends State<_ConversationCard> {
  Map<String, dynamic>? _otherUser;
  String _jobTitle = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  String get _otherUserId => widget.isEmployer
      ? widget.conversation['worker_id']
      : widget.conversation['employer_id'];

  Future<void> _loadDetails() async {
    try {
      final jobId = widget.conversation['job_id'];

      final results = await Future.wait([
        Supabase.instance.client
            .from('profiles')
            .select(
                'full_name, avatar_url, location, bio, skills, experience_level, hourly_rate, phone, rating, company_name, business_type')
            .eq('id', _otherUserId)
            .maybeSingle(),
        Supabase.instance.client
            .from('jobs')
            .select('title')
            .eq('id', jobId)
            .maybeSingle(),
      ]);

      if (mounted) {
        setState(() {
          _otherUser = results[0] as Map<String, dynamic>?;
          final job = results[1] as Map<String, dynamic>?;
          _jobTitle = job?['title'] ?? 'Job';
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading conversation detail: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _showUserProfile() {
    if (_otherUser == null) return;

    final name = _otherUser?['full_name'] ?? 'User';
    final avatarUrl = _otherUser?['avatar_url'];
    final location = _otherUser?['location'];
    final bio = _otherUser?['bio'];
    final skills = _otherUser?['skills'];
    final experience = _otherUser?['experience_level'];
    final rate = _otherUser?['hourly_rate'];
    final phone = _otherUser?['phone'];
    final profileRating = parseProfileRating(_otherUser?['rating']);
    final companyName = _otherUser?['company_name'];
    final businessType = _otherUser?['business_type'];

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
                    colors: widget.isEmployer
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
                    if (!widget.isEmployer &&
                        companyName != null &&
                        companyName.toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        companyName.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (!widget.isEmployer &&
                        businessType != null &&
                        businessType.toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        businessType.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
                    if (profileRating != null && profileRating > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ...List.generate(5, (i) {
                            final n = profileRating.round().clamp(0, 5);
                            return Icon(
                              i < n ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: const Color(0xFFF59E0B),
                              size: 22,
                            );
                          }),
                          const SizedBox(width: 8),
                          Text(
                            profileRating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        widget.isEmployer
                            ? 'Worker rating'
                            : 'Employer rating',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.72),
                        ),
                        textAlign: TextAlign.center,
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
                    if (bio != null && bio.toString().isNotEmpty) ...[
                      _profileSection(Icons.info_outline, 'About', bio.toString()),
                      const SizedBox(height: 16),
                    ],
                    if (experience != null) ...[
                      _profileSection(Icons.star_outline, 'Experience Level', experience.toString().toUpperCase()),
                      const SizedBox(height: 16),
                    ],
                    if (rate != null) ...[
                      _profileSection(Icons.payments_outlined, 'Hourly Rate', 'P$rate/hr'),
                      const SizedBox(height: 16),
                    ],
                    if (phone != null && phone.toString().isNotEmpty) ...[
                      _profileSection(Icons.phone_outlined, 'Phone', phone.toString()),
                      const SizedBox(height: 16),
                    ],
                    if (skills != null && skills is List && (skills as List).isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.build_outlined, color: widget.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Skills', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.primaryColor)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: (skills as List).map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(s.toString(), style: TextStyle(color: widget.primaryColor, fontWeight: FontWeight.w500)),
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
  }

  Widget _profileSection(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JobsyColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JobsyColors.surfaceLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: widget.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: JobsyColors.textTertiary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 15, color: JobsyColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _otherUser?['full_name'] ?? 'Loading...';
    final avatarUrl = _otherUser?['avatar_url'];
    final unreadField = widget.isEmployer ? 'employer_unread_count' : 'worker_unread_count';
    final unreadCount = widget.conversation[unreadField] ?? 0;
    final lastMessage = widget.conversation['last_message'];
    final lastMessageAt = widget.conversation['last_message_at'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JobsyColors.surfaceLight,
            JobsyColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unreadCount > 0
              ? widget.primaryColor.withOpacity(0.35)
              : JobsyColors.border.withOpacity(0.35),
          width: 0.7,
        ),
        boxShadow: unreadCount > 0
            ? [
                BoxShadow(
                  color: widget.primaryColor.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              JobsyPageRoute(
                page: ChatScreen(
                  conversationId: widget.conversation['id'],
                  otherUserName: name,
                  otherUserAvatar: avatarUrl?.toString(),
                  otherUserId: _otherUserId,
                  jobTitle: _jobTitle,
                  isEmployer: widget.isEmployer,
                ),
                transition: JobsyTransition.fadeSlide,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showUserProfile,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: widget.primaryColor.withOpacity(0.15),
                        backgroundImage: avatarUrl != null && avatarUrl.toString().isNotEmpty
                            ? NetworkImage(avatarUrl.toString()) : null,
                        child: avatarUrl == null || avatarUrl.toString().isEmpty
                            ? Text(
                                _loaded && name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(color: widget.primaryColor, fontWeight: FontWeight.bold, fontSize: 22),
                              )
                            : null,
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 0, top: 0,
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: widget.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: JobsyColors.surfaceLight, width: 2),
                            ),
                            child: Center(
                              child: Text(unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: TextStyle(
                                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 16, color: JobsyColors.textPrimary,
                                )),
                          ),
                          Text(
                            _formatTime(lastMessageAt),
                            style: TextStyle(
                              color: unreadCount > 0 ? widget.primaryColor : JobsyColors.textTertiary,
                              fontSize: 12,
                              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_jobTitle,
                            style: TextStyle(fontSize: 11, color: widget.primaryColor, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lastMessage ?? 'No messages yet',
                        style: TextStyle(
                          color: unreadCount > 0 ? JobsyColors.textPrimary : JobsyColors.textSecondary,
                          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                          fontSize: 13,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.tryParse(timestamp);
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
