import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../../services/messaging_service.dart';
import '../../services/new_rating_popup_service.dart';
import '../../config/colors.dart';
import '../../config/routes.dart';
import '../../widgets/modern_widgets.dart';
import '../../widgets/notifications_bell.dart';
import '../../config/page_transitions.dart';
import '../../services/push_notification_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/profile_rating.dart';
import '../../services/onboarding_tutorial_service.dart';
import '../../services/privacy_consent_service.dart';
import '../../services/role_service.dart';
import '../../services/profile_image_service.dart';
import '../../widgets/profile_cover_header.dart';
import '../../widgets/profile_header_avatar.dart';
import '../../widgets/role_setup_prompt.dart';
import '../../utils/location_helper.dart';
import '../../utils/maps_launcher.dart';
import '../../widgets/jobsy_app_shell.dart';
import '../../config/constants.dart';
import 'post_job_screen.dart';
import 'job_applications_screen.dart';
import '../chat/conversations_list_screen.dart';

class _RecentActivityRow {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  const _RecentActivityRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class _EmployerWorkingRow {
  final String applicationId;
  final String workerId;
  final String workerName;
  final String? workerAvatar;
  final String jobTitle;
  final String jobId;

  const _EmployerWorkingRow({
    required this.applicationId,
    required this.workerId,
    required this.workerName,
    this.workerAvatar,
    required this.jobTitle,
    required this.jobId,
  });
}

class EmployerHomeScreen extends StatefulWidget {
  const EmployerHomeScreen({super.key});
  
  @override
  State<EmployerHomeScreen> createState() => _EmployerHomeScreenState();
}

class _EmployerHomeScreenState extends State<EmployerHomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _userName = '';
  String _companyName = '';
  String _businessType = '';
  bool _isLoading = true;
  String? _avatarUrl;
  String? _coverUrl;
  double? _profileRating;
  RealtimeChannel? _employerProfileChannel;

  // Stats
  int _activeJobsCount = 0;
  int _applicationsCount = 0;
  int _completedJobsCount = 0;
  int _messagesCount = 0;
  int _unreadMessagesCount = 0;
  int _pendingApplicationsCount = 0;
  List<_RecentActivityRow> _recentActivity = [];

  // Settings
  bool _notificationsEnabled = true;
  bool _messageAlertsEnabled = true;
  String _selectedLanguage = 'English';
  bool _roleSetupPromptShown = false;
  bool _initialTabApplied = false;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (!_initialTabApplied) {
      final initialTab = args?['initialTab'] as int?;
      if (initialTab != null && initialTab >= 0 && initialTab <= 4) {
        _selectedIndex = initialTab;
      }
      _initialTabApplied = true;
    }
    if (!_roleSetupPromptShown && args?['promptRoleSetup'] == true) {
      _roleSetupPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        RoleSetupPrompt.showIfNeeded(
          context,
          role: AppConstants.userTypeEmployer,
        );
      });
    }
  }

  Future<void> _switchRole() async {
    await RoleService.confirmAndSwitch(
      context,
      targetRole: AppConstants.userTypeWorker,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.wait([_loadUserProfile(), _loadStats()]); // parallel: faster home load
    _loadLanguagePref();
    _loadNotificationPrefs();
    _subscribeEmployerProfileRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(NewRatingPopupService.check(context, isEmployer: true));
      unawaited(OnboardingTutorialService.maybeShow(context));
    });
  }

  void _subscribeEmployerProfileRealtime() {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    _employerProfileChannel?.unsubscribe();
    _employerProfileChannel = Supabase.instance.client
        .channel('employer-profile-live-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: myId,
          ),
          callback: (_) {
            if (mounted) _loadUserProfile();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _employerProfileChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUserProfile();
      _loadStats();
      unawaited(NewRatingPopupService.check(context, isEmployer: true));
    }
  }

  Future<List<_EmployerWorkingRow>> _resolveEmployerWorkingWith(
    String employerId,
    List<Map<String, dynamic>> applications,
    List<Map<String, dynamic>> employerJobs,
  ) async {
    final jobById = {for (final j in employerJobs) j['id'] as String: j};
    final active = applications.where((a) {
      final s = a['status'] as String?;
      final jid = a['job_id'] as String;
      final j = jobById[jid];
      return j != null &&
          j['employer_id'] == employerId &&
          (s == 'accepted' || s == 'in_progress');
    }).toList();
    if (active.isEmpty) return [];

    final workerIds =
        active.map((a) => a['worker_id'] as String).toSet().toList();
    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', workerIds);
    final pMap = {for (final p in profiles as List) p['id']: p};

    return active.map((a) {
      final w = pMap[a['worker_id']] as Map<String, dynamic>?;
      final j = jobById[a['job_id'] as String]!;
      return _EmployerWorkingRow(
        applicationId: a['id'] as String,
        workerId: a['worker_id'] as String,
        workerName: w?['full_name'] as String? ?? 'Worker',
        workerAvatar: w?['avatar_url'] as String?,
        jobTitle: j['title'] as String? ?? 'Job',
        jobId: a['job_id'] as String,
      );
    }).toList();
  }

  Widget _buildEmployerWorkingWithStrip(List<_EmployerWorkingRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Working with',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: JobsyColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    MessagingService.openChat(
                      context: context,
                      applicationId: r.applicationId,
                      jobId: r.jobId,
                      jobTitle: r.jobTitle,
                      employerId: myId,
                      workerId: r.workerId,
                      otherUserName: r.workerName,
                      isEmployer: true,
                      otherUserAvatar: r.workerAvatar,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              JobsyColors.employerPrimary.withOpacity(0.2),
                          backgroundImage: r.workerAvatar != null &&
                                  r.workerAvatar!.isNotEmpty
                              ? NetworkImage(r.workerAvatar!)
                              : null,
                          child: r.workerAvatar == null || r.workerAvatar!.isEmpty
                              ? Text(
                                  r.workerName.isNotEmpty
                                      ? r.workerName[0].toUpperCase()
                                      : 'W',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: JobsyColors.employerPrimary,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.workerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: JobsyColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.jobTitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: JobsyColors.textSecondary.withOpacity(0.95),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            MessagingService.openChat(
                              context: context,
                              applicationId: r.applicationId,
                              jobId: r.jobId,
                              jobTitle: r.jobTitle,
                              employerId: myId,
                              workerId: r.workerId,
                              otherUserName: r.workerName,
                              isEmployer: true,
                              otherUserAvatar: r.workerAvatar,
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded,
                              size: 18),
                          label: const Text('Message'),
                          style: TextButton.styleFrom(
                            foregroundColor: JobsyColors.employerPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
  
  Future<void> _loadLanguagePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('language');
      if (saved != null && mounted) {
        setState(() => _selectedLanguage = saved);
      }
    } catch (_) {}
  }
  
  Future<void> _saveLanguagePref(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', lang);
    } catch (_) {}
  }

  Future<void> _loadNotificationPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifEnabled = prefs.getBool('notifications_enabled') ?? true;
      final msgEnabled = prefs.getBool('message_alerts_enabled') ?? true;
      if (mounted) {
        setState(() {
          _notificationsEnabled = notifEnabled;
          _messageAlertsEnabled = msgEnabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleNotifications(bool enabled) async {
    setState(() => _notificationsEnabled = enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);

      // Update the server-side flag so the Edge Function respects it
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('profiles').update({
          'notifications_enabled': enabled,
        }).eq('id', userId);
      }
    } catch (e) {
      debugPrint('Toggle notifications error: $e');
    }
  }

  Future<void> _toggleMessageAlerts(bool enabled) async {
    setState(() => _messageAlertsEnabled = enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('message_alerts_enabled', enabled);

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('profiles').update({
          'message_alerts_enabled': enabled,
        }).eq('id', userId);
      }
    } catch (e) {
      debugPrint('Toggle message alerts error: $e');
    }
  }
  
  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      const fullSelect =
          'full_name, company_name, business_type, avatar_url, cover_url, rating';
      const withoutCover =
          'full_name, company_name, business_type, avatar_url, rating';
      const baseSelect = 'full_name, company_name, business_type, rating';

      Map<String, dynamic>? response;
      for (final fields in [fullSelect, withoutCover, baseSelect]) {
        try {
          response = await Supabase.instance.client
              .from('profiles')
              .select(fields)
              .eq('id', userId)
              .maybeSingle();
          break;
        } catch (e) {
          debugPrint('Profile select fallback ($fields): $e');
          response = null;
        }
      }

      if (!mounted) return;

      if (response != null) {
        setState(() {
          _userName = response!['full_name'] ?? '';
          _companyName = response['company_name'] ?? '';
          _businessType = response['business_type'] ?? '';
          _avatarUrl = response['avatar_url'];
          _coverUrl = response['cover_url'];
          _profileRating = parseProfileRating(response['rating']);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _loadStats() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final jobsList = await Supabase.instance.client
          .from('jobs')
          .select('id, status')
          .eq('employer_id', userId);

      final list = (jobsList as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final activeJobs = list
          .where((j) =>
              j['status'] == 'active' || j['status'] == 'in_progress')
          .toList();
      final completedJobs = list
          .where((j) =>
              j['status'] == 'completed' || j['status'] == 'cancelled')
          .toList();

      // Get applications count (for all employer's jobs)
      final jobIds = activeJobs.map((j) => j['id'] as String).toList();
      final completedJobIds =
          completedJobs.map((j) => j['id'] as String).toList();
      final allJobIds = [...jobIds, ...completedJobIds];
      
      int appCount = 0;
      int pendingCount = 0;
      int totalUnread = 0;

      if (allJobIds.isNotEmpty) {
        final batch = await Future.wait([
          Supabase.instance.client
              .from('job_applications')
              .select('id')
              .inFilter('job_id', allJobIds),
          Supabase.instance.client
              .from('conversations')
              .select('employer_unread_count')
              .eq('employer_id', userId)
              .eq('inbox_visible', true),
          Supabase.instance.client
              .from('job_applications')
              .select('id')
              .inFilter('job_id', allJobIds)
              .eq('status', 'pending'),
        ]);
        appCount = (batch[0] as List).length;
        pendingCount = (batch[2] as List).length;
        for (final c in (batch[1] as List)) {
          totalUnread += (c['employer_unread_count'] as int? ?? 0);
        }
      } else {
        final conversations = await Supabase.instance.client
            .from('conversations')
            .select('employer_unread_count')
            .eq('employer_id', userId)
            .eq('inbox_visible', true);
        for (final c in (conversations as List)) {
          totalUnread += (c['employer_unread_count'] as int? ?? 0);
        }
      }
      
      if (mounted) {
        setState(() {
          _activeJobsCount = activeJobs.length;
          _completedJobsCount = completedJobs.length;
          _applicationsCount = appCount;
          _messagesCount = totalUnread;
          _unreadMessagesCount = totalUnread;
          _pendingApplicationsCount = pendingCount;
        });
      }

      await _refreshRecentActivity(userId);
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  /// Timeline of recent jobs + applications (stats alone did not populate UI).
  Future<void> _refreshRecentActivity(String userId) async {
    try {
      final jobsResponse = await Supabase.instance.client
          .from('jobs')
          .select('id, title, status, created_at')
          .eq('employer_id', userId)
          .order('created_at', ascending: false)
          .limit(12);

      final items = <Map<String, dynamic>>[];

      for (final j in (jobsResponse as List)) {
        final createdAt = DateTime.tryParse(j['created_at'] as String? ?? '');
        if (createdAt == null) continue;
        final status = (j['status'] as String?) ?? 'active';
        final title = (j['title'] as String?) ?? 'Job';
        String subtitle;
        IconData icon;
        Color accent;
        switch (status) {
          case 'completed':
            subtitle = 'Completed';
            icon = Icons.check_circle_outline_rounded;
            accent = JobsyColors.workerPrimary;
            break;
          case 'cancelled':
            subtitle = 'Cancelled';
            icon = Icons.block_rounded;
            accent = const Color(0xFF94A3B8);
            break;
          case 'in_progress':
            subtitle = 'In progress';
            icon = Icons.play_circle_outline_rounded;
            accent = const Color(0xFF10B981);
            break;
          default:
            subtitle = 'Open for applications';
            icon = Icons.work_outline_rounded;
            accent = JobsyColors.employerPrimary;
        }
        items.add({
          'at': createdAt,
          'row': _RecentActivityRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
          ),
        });
      }

      final allJobIds = (jobsResponse as List).map((e) => e['id'] as String).toList();
      if (allJobIds.isNotEmpty) {
        try {
          final apps = await Supabase.instance.client
              .from('job_applications')
              .select('status, created_at, jobs(title), profiles(full_name)')
              .inFilter('job_id', allJobIds)
              .order('created_at', ascending: false)
              .limit(15);

          for (final a in (apps as List)) {
            final createdAt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (createdAt == null) continue;
            final st = (a['status'] as String?) ?? 'pending';
            final jobTitle = (a['jobs'] is Map)
                ? ((a['jobs'] as Map)['title'] as String?) ?? 'Job'
                : 'Job';
            final workerName = (a['profiles'] is Map)
                ? ((a['profiles'] as Map)['full_name'] as String?) ?? 'Worker'
                : 'Worker';

            String subtitle;
            IconData icon;
            const accent = Color(0xFF10B981);
            switch (st) {
              case 'pending':
                subtitle = '$workerName applied · $jobTitle';
                icon = Icons.person_add_alt_1_rounded;
                break;
              case 'accepted':
              case 'in_progress':
                subtitle = '$workerName working on · $jobTitle';
                icon = Icons.handshake_rounded;
                break;
              case 'completed':
                subtitle = '$workerName completed · $jobTitle';
                icon = Icons.emoji_events_outlined;
                break;
              case 'rejected':
                subtitle = 'Application declined · $jobTitle';
                icon = Icons.cancel_outlined;
                break;
              case 'withdrawn':
                subtitle = 'Worker withdrew · $jobTitle';
                icon = Icons.exit_to_app_rounded;
                break;
              case 'cancelled':
                subtitle = 'Hiring closed · $jobTitle';
                icon = Icons.block_rounded;
                break;
              default:
                subtitle = 'Application updated · $jobTitle';
                icon = Icons.info_outline_rounded;
            }
            items.add({
              'at': createdAt,
              'row': _RecentActivityRow(
                title: workerName,
                subtitle: subtitle,
                icon: icon,
                accent: accent,
              ),
            });
          }
        } catch (e) {
          debugPrint('Recent activity applications sub-query: $e');
          // Fall back to jobs-only if FK hint fails in some DBs
          final apps = await Supabase.instance.client
              .from('job_applications')
              .select('status, created_at, job_id, jobs(title)')
              .inFilter('job_id', allJobIds)
              .order('created_at', ascending: false)
              .limit(15);
          for (final a in (apps as List)) {
            final createdAt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (createdAt == null) continue;
            final st = (a['status'] as String?) ?? 'pending';
            final jobTitle = (a['jobs'] is Map)
                ? ((a['jobs'] as Map)['title'] as String?) ?? 'Job'
                : 'Job';
            items.add({
              'at': createdAt,
              'row': _RecentActivityRow(
                title: st == 'pending' ? 'New application' : 'Application update',
                subtitle: '$st · $jobTitle',
                icon: Icons.notifications_active_outlined,
                accent: JobsyColors.employerPrimary,
              ),
            });
          }
        }
      }

      items.sort((a, b) => (b['at'] as DateTime).compareTo(a['at'] as DateTime));
      final rows = items
          .take(10)
          .map((m) => m['row'] as _RecentActivityRow)
          .toList();

      if (mounted) setState(() => _recentActivity = rows);
    } catch (e) {
      debugPrint('Recent activity: $e');
    }
  }
  
  void _showEditProfileDialog() async {
    // Load current profile data
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId!)
          .single();
      
      final nameController = TextEditingController(text: profileData['full_name'] ?? '');
      final phoneController = TextEditingController(text: profileData['phone'] ?? '');
      final locationController = TextEditingController(text: profileData['location'] ?? '');
      final companyController = TextEditingController(text: profileData['company_name'] ?? '');
      String? selectedBusinessType = profileData['business_type'];
      
      final businessTypes = [
        'Construction',
        'Retail',
        'Hospitality',
        'Technology',
        'Healthcare',
        'Education',
        'Agriculture',
        'Manufacturing',
        'Services',
        'Other',
      ];
      
      final otherBusinessTypeController = TextEditingController();
      bool showOtherBusinessField = selectedBusinessType == 'Other' || 
          (selectedBusinessType != null && !businessTypes.contains(selectedBusinessType));
      if (showOtherBusinessField && selectedBusinessType != null && selectedBusinessType != 'Other') {
        otherBusinessTypeController.text = selectedBusinessType!;
      }
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.7),
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    JobsyColors.surfaceLight,
                    JobsyColors.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: JobsyColors.employerPrimary.withOpacity(0.15),
                  width: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: JobsyColors.employerPrimary.withOpacity(0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cinematic gradient header
                  const JobsyDialogHeader(
                    icon: Icons.badge_rounded,
                    title: 'My Info',
                    subtitle: 'Update your personal and business details',
                    accentColor: JobsyColors.employerPrimary,
                  ),
                  // Scrollable content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Personal section
                          _buildDialogSectionLabel('Personal', Icons.person_outline_rounded),
                          const SizedBox(height: 14),
                          JobsyTextField(
                            controller: nameController,
                            label: 'Full Name',
                            hint: 'Your full name',
                            prefixIcon: Icons.person_rounded,
                            accentColor: JobsyColors.employerPrimary,
                          ),
                          const SizedBox(height: 16),
                          JobsyTextField(
                            controller: phoneController,
                            label: 'Phone Number',
                            hint: '+267 XX XXX XXX',
                            prefixIcon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                            accentColor: JobsyColors.employerPrimary,
                          ),
                          const SizedBox(height: 16),
                          JobsyTextField(
                            controller: locationController,
                            label: 'Location',
                            hint: 'City or area',
                            prefixIcon: Icons.location_on_rounded,
                            accentColor: JobsyColors.employerPrimary,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final label = await LocationHelper.getCurrentAreaLabel();
                                if (label != null) {
                                  setDialogState(() => locationController.text = label);
                                }
                              },
                              icon: const Icon(Icons.my_location_rounded, size: 16),
                              label: const Text('Use my location'),
                            ),
                          ),
                          const SizedBox(height: 28),
                          // Business section
                          _buildDialogSectionLabel('Business', Icons.business_outlined),
                          const SizedBox(height: 14),
                          JobsyTextField(
                            controller: companyController,
                            label: 'Company Name',
                            hint: 'Your company or business',
                            prefixIcon: Icons.business_rounded,
                            accentColor: JobsyColors.employerPrimary,
                          ),
                          const SizedBox(height: 16),
                          // Custom dark-theme dropdown
                          _buildDialogDropdown(
                            label: 'Business Type',
                            value: selectedBusinessType,
                            hint: 'e.g. Construction, Retail, Hospitality',
                            items: businessTypes,
                            icon: Icons.work_rounded,
                            accentColor: JobsyColors.employerPrimary,
                            onChanged: (value) {
                              setDialogState(() {
                                selectedBusinessType = value;
                                showOtherBusinessField = value == 'Other';
                                if (value != 'Other') {
                                  otherBusinessTypeController.clear();
                                }
                              });
                            },
                          ),
                          if (showOtherBusinessField) ...[
                            const SizedBox(height: 16),
                            JobsyTextField(
                              controller: otherBusinessTypeController,
                              label: 'Specify Type',
                              hint: 'e.g. Real Estate, Consulting',
                              prefixIcon: Icons.add_circle_outline_rounded,
                              accentColor: JobsyColors.employerPrimary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Action bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: JobsyColors.border.withOpacity(0.6),
                                  width: 0.7,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: JobsyColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: JobsyGradientButton(
                            text: 'Save Changes',
                            icon: Icons.check_rounded,
                            gradient: JobsyColors.employerGradient,
                            height: 48,
                            fontSize: 14,
                            onPressed: () async {
                  try {
                    final updates = <String, dynamic>{
                      'full_name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'location': locationController.text.trim(),
                    };
                    
                    // Only update employer fields if values are provided
                    if (companyController.text.trim().isNotEmpty) {
                      updates['company_name'] = companyController.text.trim();
                    }
                    if (selectedBusinessType != null) {
                      // If "Other" is selected and custom text provided, use custom text
                      if (selectedBusinessType == 'Other' && otherBusinessTypeController.text.trim().isNotEmpty) {
                        updates['business_type'] = otherBusinessTypeController.text.trim();
                      } else if (selectedBusinessType != 'Other') {
                        updates['business_type'] = selectedBusinessType;
                      }
                    }
                    
                    await Supabase.instance.client
                        .from('profiles')
                        .update(updates)
                        .eq('id', userId);
                    
                    setState(() {
                      _userName = nameController.text.trim();
                      _companyName = companyController.text.trim();
                      _businessType = selectedBusinessType ?? '';
                    });
                    
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text('Profile updated successfully!'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(friendlyErrorMessage(e)),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                            },
                          ),
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
    } catch (e) {
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
  
  // Section label used inside dialogs — small uppercase pill with gradient dot
  Widget _buildDialogSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: JobsyColors.employerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: JobsyColors.employerPrimary.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: JobsyColors.employerOnAccent, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: JobsyColors.textTertiary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 0.6,
            color: JobsyColors.border.withOpacity(0.4),
          ),
        ),
      ],
    );
  }
  
  // Custom dark-themed dropdown to match JobsyTextField visual language
  Widget _buildDialogDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required Color accentColor,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: JobsyColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: JobsyColors.inputBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: JobsyColors.border.withOpacity(0.5),
              width: 0.7,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            hint: Text(
              hint ?? 'Select an option',
              style: const TextStyle(
                color: JobsyColors.textSecondary,
                fontSize: 15,
              ),
            ),
            dropdownColor: JobsyColors.surfaceElevated,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: accentColor.withOpacity(0.8),
            ),
            style: const TextStyle(
              fontSize: 16,
              color: JobsyColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: accentColor.withOpacity(0.8),
                size: 20,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            borderRadius: BorderRadius.circular(14),
            items: items.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(
                  type,
                  style: const TextStyle(
                    color: JobsyColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
  
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    // Refresh stats when returning to home or switching tabs
    if (index == 0) _loadStats();
    // Clear message badge when entering messages tab
    if (index == 3) {
      setState(() => _unreadMessagesCount = 0);
    }
  }
  
  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await PushNotificationService.instance.clearToken();
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.welcome,
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign out failed. Please try again.')),
          );
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // If not on first tab, go back to previous tab
        if (_selectedIndex > 0) {
          setState(() => _selectedIndex--);
          return false; // Don't exit app
        }
        // If on first tab, exit app
        return true;
      },
      child: Scaffold(
        backgroundColor: JobsyColors.background,
        body: SafeArea(
        child: Column(
          children: [
            JobsyAppBar(
              accentColor: JobsyColors.employerPrimary,
              isEmployer: true,
              userName: _userName,
              avatarUrl: _avatarUrl,
              onLeadingPressed: _handleSignOut,
              onProfileTap: () => setState(() => _selectedIndex = 4),
            ),
            
            // Main content
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildHomeTab(),
                  _buildMyJobsTab(),
                  _buildWalletTab(),
                  _buildMessagesTab(),
                  _buildProfileTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      
      bottomNavigationBar: JobsyBottomNav(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        accentColor: JobsyColors.employerPrimary,
        items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: _pendingApplicationsCount > 0
                  ? Badge(
                      label: Text(_pendingApplicationsCount > 9 ? '9+' : '$_pendingApplicationsCount',
                          style: const TextStyle(fontSize: 10, color: Colors.white)),
                      child: const Icon(Icons.work_outline),
                    )
                  : const Icon(Icons.work_outline),
              activeIcon: const Icon(Icons.work),
              label: 'My Jobs',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: 'Wallet',
            ),
            BottomNavigationBarItem(
              icon: _unreadMessagesCount > 0
                  ? Badge(
                      label: Text(_unreadMessagesCount > 9 ? '9+' : '$_unreadMessagesCount',
                          style: const TextStyle(fontSize: 10, color: Colors.white)),
                      child: const Icon(Icons.message_outlined),
                    )
                  : const Icon(Icons.message_outlined),
              activeIcon: const Icon(Icons.message),
              label: 'Messages',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
        ],
      ),
      ),
    );
  }
  
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back${_userName.isNotEmpty ? ", $_userName" : ""}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: JobsyColors.textPrimary,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: JobsyColors.employerPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Expanded(
                child: Text(
                  'Your hiring dashboard — post roles and manage applicants',
                  style: TextStyle(
                    fontSize: 14,
                    color: JobsyColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 28),
          
          // Post Job button — gradient with glow, press-scale
          AnimatedPressButton(
            scaleDown: 0.97,
            onPressed: () async {
              final result = await Navigator.push(
                context,
                JobsyPageRoute(
                  page: const PostJobScreen(),
                  transition: JobsyTransition.fadeSlide,
                ),
              );
              if (result == true) {
                _loadStats();
              }
            },
            child: Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: JobsyColors.employerGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: JobsyColors.employerPrimary.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: JobsyColors.employerOnAccent.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded, size: 22, color: JobsyColors.employerOnAccent),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Post a Job',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.employerOnAccent,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Quick stats
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: JobsyColors.employerGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: JobsyColors.employerPrimary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.insights_rounded, size: 16, color: JobsyColors.employerOnAccent),
              ),
              const SizedBox(width: 10),
              const Text(
                'Your Stats',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: JobsyColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Active Jobs',
                  _activeJobsCount.toString(),
                  Icons.work,
                  JobsyColors.employerPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Applications',
                  _applicationsCount.toString(),
                  Icons.person,
                  const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Completed',
                  _completedJobsCount.toString(),
                  Icons.check_circle,
                  JobsyColors.workerPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Messages',
                  _messagesCount.toString(),
                  Icons.message,
                  const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Recent activity
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.timeline_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: JobsyColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (_recentActivity.isEmpty)
            Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  JobsyColors.surfaceLight,
                  JobsyColors.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: JobsyColors.employerPrimary.withOpacity(0.18),
                width: 0.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: JobsyColors.employerPrimary.withOpacity(0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        JobsyColors.employerPrimary.withOpacity(0.18),
                        JobsyColors.employerPrimary.withOpacity(0.04),
                      ],
                    ),
                    border: Border.all(
                      color: JobsyColors.employerPrimary.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.inbox_rounded,
                    size: 38,
                    color: JobsyColors.employerPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No activity yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Post your first job to get started',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: JobsyColors.textTertiary,
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
          else
            Column(
              children: _recentActivity
                  .map((row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildRecentActivityTile(row),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
  
  Widget _buildRecentActivityTile(_RecentActivityRow row) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JobsyColors.surfaceLight,
            JobsyColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: row.accent.withOpacity(0.22),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: row.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(row.icon, color: row.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: JobsyColors.textTertiary.withOpacity(0.95),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JobsyColors.surfaceLight,
            JobsyColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 0.6,
              ),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: JobsyColors.textPrimary,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              color: JobsyColors.textTertiary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMyJobsTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Immersive gradient header with glow orb
          ClipRect(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF14141C),
                    Color(0xFF1A1A2E),
                    Color(0xFF0E0E14),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 150,
                      height: 150,
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
                  Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 0.7,
                              ),
                            ),
                            child: const Icon(Icons.work_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) => const LinearGradient(
                                    colors: [
                                      Color(0xFFFFFFFF),
                                      Color(0xFFCBD5E1),
                                      Color(0xFFFFFFFF),
                                    ],
                                    stops: [0.0, 0.5, 1.0],
                                  ).createShader(bounds),
                                  child: const Text(
                                    'My Jobs',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Manage your posted jobs',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white.withOpacity(0.75),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedPressButton(
                            scaleDown: 0.9,
                            onPressed: () {},
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                  width: 0.7,
                                ),
                              ),
                              child: const Icon(Icons.filter_list_rounded,
                                  color: Colors.white, size: 19),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Pill-style segmented tab bar
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 0.6,
                          ),
                        ),
                        child: TabBar(
                          labelColor: JobsyColors.employerOnAccent,
                          unselectedLabelColor: Colors.white.withOpacity(0.65),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          tabs: [
                            Tab(text: 'Active ($_activeJobsCount)'),
                            Tab(text: 'Past ($_completedJobsCount)'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Tab views
          Expanded(
            child: TabBarView(
              children: [
                _buildActiveJobsList(),
                _buildCompletedJobsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActiveJobsList() {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('job_applications')
          .stream(primaryKey: ['id']),
      builder: (context, appSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('jobs')
              .stream(primaryKey: ['id'])
              .eq('employer_id', userId ?? '')
              .order('created_at', ascending: false),
          builder: (context, jobSnapshot) {
            if (jobSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    friendlyStreamError(jobSnapshot.error),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: JobsyColors.textSecondary),
                  ),
                ),
              );
            }

            if (!jobSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allJobs = jobSnapshot.data!;
            final jobs = allJobs.where((job) {
              final status = job['status'];
              return status == 'active' || status == 'in_progress';
            }).toList();

            final jobIdSet =
                allJobs.map<String>((j) => j['id'] as String).toSet();
            final apps = (appSnapshot.data ?? []).where((a) {
              return jobIdSet.contains(a['job_id']) &&
                  (a['status'] == 'accepted' || a['status'] == 'in_progress');
            }).toList();

            final activeCount = jobs.length;
            final completedCount = allJobs
                .where((j) =>
                    j['status'] == 'completed' || j['status'] == 'cancelled')
                .length;
            if (_activeJobsCount != activeCount ||
                _completedJobsCount != completedCount) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _activeJobsCount = activeCount;
                    _completedJobsCount = completedCount;
                  });
                }
              });
            }

            final stripFuture = userId != null
                ? _resolveEmployerWorkingWith(userId, apps, allJobs)
                : Future<List<_EmployerWorkingRow>>.value(const []);

            final listSection = jobs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: JobsyColors.surfaceLight,
                              border: Border.all(
                                color: JobsyColors.employerPrimary.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.work_outline_rounded,
                              size: 42,
                              color: JobsyColors.employerPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No active jobs',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: JobsyColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Post a job to get started',
                            style: TextStyle(
                              fontSize: 14,
                              color: JobsyColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return AnimatedListItem(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildJobCardFromData(job, isCompleted: false),
                        ),
                      );
                    },
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<List<_EmployerWorkingRow>>(
                  key: ValueKey(
                    apps.map((a) => '${a['id']}-${a['status']}').join('|'),
                  ),
                  future: stripFuture,
                  builder: (context, stripSnap) {
                    if (!stripSnap.hasData || stripSnap.data!.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _buildEmployerWorkingWithStrip(stripSnap.data!);
                  },
                ),
                Expanded(child: listSection),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _buildCompletedJobsList() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    return StreamBuilder(
      stream: Supabase.instance.client
          .from('jobs')
          .stream(primaryKey: ['id'])
          .eq('employer_id', userId ?? '')
          .order('created_at', ascending: false),
      builder: (context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                friendlyStreamError(snapshot.error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: JobsyColors.textSecondary),
              ),
            ),
          );
        }
        
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: JobsyColors.employerPrimary));
        }
        
        // Past: finished or cancelled by employer
        final jobs = snapshot.data!.where((job) {
          final s = job['status'];
          return s == 'completed' || s == 'cancelled';
        }).toList();
        
        if (jobs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JobsyColors.surfaceLight,
                      border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 42,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No past jobs yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Completed and cancelled jobs appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: JobsyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            final isCancelled = job['status'] == 'cancelled';
            return AnimatedListItem(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildJobCardFromData(job,
                    isCompleted: true, forceCancelled: isCancelled),
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildJobCardFromData(Map<String, dynamic> job,
      {required bool isCompleted, bool forceCancelled = false}) {
    final status = job['status'] as String?;
    final statusColor = forceCancelled || status == 'cancelled'
        ? const Color(0xFF94A3B8)
        : status == 'completed'
            ? const Color(0xFF10B981)
            : status == 'in_progress'
                ? const Color(0xFFF59E0B)
                : JobsyColors.employerPrimary;
    final statusLabel = status == 'active'
        ? 'Active'
        : status == 'in_progress'
            ? 'In Progress'
            : (status == 'cancelled' ? 'Cancelled' : 'Completed');
    
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JobsyColors.surfaceLight,
            JobsyColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + budget pill
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        job['title'] ?? 'Untitled Job',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: JobsyColors.textPrimary,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        'P${job['budget_amount'] ?? '0'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Location pill
                _buildInfoPill(
                  icon: Icons.location_on_rounded,
                  text: job['location'] ?? 'No location',
                  tint: JobsyColors.employerPrimary,
                ),
                const SizedBox(height: 8),
                // Date pill
                _buildInfoPill(
                  icon: Icons.calendar_today_rounded,
                  text: job['created_at'] != null
                      ? job['created_at'].toString().substring(0, 10)
                      : 'No date',
                  tint: JobsyColors.textSecondary,
                ),
                const SizedBox(height: 12),
                // Status pill with glowing dot
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: statusColor.withOpacity(0.35),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withOpacity(0.6),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            color: JobsyColors.border.withOpacity(0.35),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedPressButton(
                    scaleDown: 0.96,
                    onPressed: () {
                      Navigator.push(
                        context,
                        JobsyPageRoute(
                          page: JobApplicationsScreen(
                            jobId: job['id'],
                            jobTitle: job['title'] ?? 'Job',
                          ),
                          transition: JobsyTransition.fadeSlide,
                        ),
                      );
                    },
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: JobsyColors.employerPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: JobsyColors.employerPrimary.withOpacity(0.4),
                          width: 0.7,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Applications',
                          style: TextStyle(
                            color: JobsyColors.employerPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedPressButton(
                    scaleDown: 0.96,
                    onPressed: () {
                      _showJobDetailsSheet(job);
                    },
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: JobsyColors.employerGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: JobsyColors.employerPrimary.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'View Details',
                          style: TextStyle(
                            color: JobsyColors.employerOnAccent,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoPill({
    required IconData icon,
    required String text,
    required Color tint,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: tint.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: tint),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: JobsyColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  void _showJobDetailsSheet(Map<String, dynamic> job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: JobsyColors.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: JobsyColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF14141C),
                        Color(0xFF1A1A2E),
                        Color(0xFF0E0E14),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -30,
                        right: -30,
                        child: Container(
                          width: 150,
                          height: 150,
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [
                                        Color(0xFFFFFFFF),
                                        Color(0xFFCBD5E1),
                                        Color(0xFFFFFFFF),
                                      ],
                                      stops: [0.0, 0.5, 1.0],
                                    ).createShader(bounds),
                                    child: Text(
                                      job['title'] ?? 'Untitled Job',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.4,
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    'P${job['budget_amount']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.25),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    (job['budget_type'] ?? 'fixed').toString().toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.25),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        (job['status'] ?? 'active')
                                            .toString()
                                            .replaceAll('_', ' ')
                                            .split(' ')
                                            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                                            .join(' '),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    _detailRow(
                      Icons.location_on,
                      'Location',
                      job['location'] ?? 'Not set',
                      onTap: (job['location']?.toString().trim().isNotEmpty ?? false)
                          ? () => MapsLauncher.openJobLocation(job)
                          : null,
                      trailing: MapsLauncher.hasJobCoordinates(job)
                          ? 'GPS pin'
                          : null,
                    ),
                    _detailRow(Icons.category, 'Category', job['category'] ?? 'Not set'),
                    _detailRow(Icons.calendar_today, 'Posted',
                        job['created_at'] != null ? job['created_at'].toString().substring(0, 10) : 'N/A'),
                    if (job['start_date'] != null)
                      _detailRow(Icons.event, 'Start Date', job['start_date'].toString().substring(0, 10)),
                    if (job['duration_days'] != null)
                      _detailRow(Icons.timelapse, 'Duration', '${job['duration_days']} days'),
                    if (job['experience_level'] != null)
                      _detailRow(Icons.star, 'Experience', job['experience_level'].toString()),
                    
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.description_outlined, color: JobsyColors.employerPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text('Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: JobsyColors.employerPrimary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      job['description'] ?? 'No description provided.',
                      style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary, height: 1.5),
                    ),
                    
                    if (job['required_skills'] != null && (job['required_skills'] as List).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.build_outlined, color: JobsyColors.employerPrimary, size: 20),
                          const SizedBox(width: 8),
                          Text('Required Skills', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: JobsyColors.employerPrimary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (job['required_skills'] as List).map((skill) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: JobsyColors.employerPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(skill.toString(), style: const TextStyle(
                            color: JobsyColors.employerPrimary, fontWeight: FontWeight.w600, fontSize: 13,
                          )),
                        )).toList(),
                      ),
                    ],
                    
                    if (job['job_photos'] != null && (job['job_photos'] as List).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.photo_library_outlined, color: JobsyColors.employerPrimary, size: 20),
                          const SizedBox(width: 8),
                          Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: JobsyColors.employerPrimary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: (job['job_photos'] as List).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              (job['job_photos'] as List)[i],
                              width: 120, height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120, height: 120,
                                color: JobsyColors.surfaceLight,
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 30),
                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                JobsyPageRoute(
                                  page: JobApplicationsScreen(
                                    jobId: job['id'],
                                    jobTitle: job['title'] ?? 'Job',
                                  ),
                                  transition: JobsyTransition.fadeSlide,
                                ),
                              );
                            },
                            icon: const Icon(Icons.people, size: 20),
                            label: const Text('Applications'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: JobsyColors.employerPrimary,
                              side: const BorderSide(color: JobsyColors.employerPrimary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditJobSheet(job);
                            },
                            icon: const Icon(Icons.edit, size: 20),
                            label: const Text('Edit Job'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: JobsyColors.employerPrimary,
                              foregroundColor: JobsyColors.employerOnAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (((job['status'] as String?) == 'active' ||
                        (job['status'] as String?) == 'in_progress'))
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmCancelJob(job);
                          },
                          icon: const Icon(Icons.cancel_outlined, size: 20),
                          label: const Text('End hire & reopen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59E0B),
                            side: const BorderSide(color: Color(0xFFF59E0B)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    if (((job['status'] as String?) == 'active' ||
                        (job['status'] as String?) == 'in_progress'))
                      const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDeleteJob(job);
                        },
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const Text('Delete Job'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
    String? trailing,
  }) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: JobsyColors.employerPrimary),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 14, color: JobsyColors.textSecondary,
          )),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, color: JobsyColors.textPrimary)),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: JobsyColors.employerPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailing,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.employerPrimary.withValues(alpha: 0.9),
                ),
              ),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.directions_rounded,
                size: 18, color: JobsyColors.employerPrimary.withValues(alpha: 0.8)),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: row);
  }
  
  // ── Cancel job (employer) ──────────────────────────
  void _confirmCancelJob(Map<String, dynamic> job) {
    final title = job['title'] ?? 'this job';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Color(0xFFF59E0B), size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'End hire & reopen listing?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '“$title” goes back to an active listing. Current hires and pending applicants are closed out; chat threads for this round are hidden from Messages for both sides. Affected workers are notified.',
          style: const TextStyle(
              color: JobsyColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep job'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performCancelJob(job);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reopen listing'),
          ),
        ],
      ),
    );
  }

  Future<void> _performCancelJob(Map<String, dynamic> job) async {
    final jobId = job['id'] as String;
    final empId = Supabase.instance.client.auth.currentUser?.id;
    if (empId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      // Close out applications first so inbox visibility triggers see a consistent state.
      await Supabase.instance.client.from('job_applications').update({
        'status': 'cancelled',
        'updated_at': now,
      }).eq('job_id', jobId).inFilter('status', ['pending', 'accepted', 'in_progress']);

      await Supabase.instance.client.from('jobs').update({
        'status': 'active',
        'updated_at': now,
      }).eq('id', jobId).eq('employer_id', empId);

      if (mounted) {
        _loadStats();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing is active again. Workers were notified.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
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

  // ── Delete Job ─────────────────────────────────────
  void _confirmDeleteJob(Map<String, dynamic> job) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Delete Job', style: TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this job?',
              style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JobsyColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JobsyColors.surfaceLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.work, size: 18, color: JobsyColors.employerPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      job['title'] ?? 'Untitled',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.red[300]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will also remove all applications and conversations for this job. This action cannot be undone.',
                      style: TextStyle(fontSize: 12, color: Colors.red[400], height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: JobsyColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteJob(job['id']);
            },
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteJob(String jobId) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      
      // Delete related messages first
      try {
        final conversations = await Supabase.instance.client
            .from('conversations')
            .select('id')
            .eq('job_id', jobId);
        
        for (final conv in (conversations as List)) {
          await Supabase.instance.client
              .from('messages')
              .delete()
              .eq('conversation_id', conv['id']);
        }
        
        // Delete conversations
        await Supabase.instance.client
            .from('conversations')
            .delete()
            .eq('job_id', jobId);
      } catch (e) {
        debugPrint('Cleaning up conversations: $e');
      }
      
      // Delete applications
      try {
        await Supabase.instance.client
            .from('job_applications')
            .delete()
            .eq('job_id', jobId);
      } catch (e) {
        debugPrint('Cleaning up applications: $e');
      }
      
      // Delete the job
      await Supabase.instance.client
          .from('jobs')
          .delete()
          .eq('id', jobId);
      
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        _loadStats(); // Refresh stats
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: JobsyColors.surfaceLight, size: 20),
                SizedBox(width: 8),
                Text('Job deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // ── Edit Job ───────────────────────────────────────
  void _showEditJobSheet(Map<String, dynamic> job) {
    final titleController = TextEditingController(text: job['title'] ?? '');
    final descController = TextEditingController(text: job['description'] ?? '');
    final locationController = TextEditingController(text: job['location'] ?? '');
    final budgetController = TextEditingController(
      text: job['budget_amount']?.toString() ?? '',
    );
    final durationController = TextEditingController(
      text: job['duration_days']?.toString() ?? '',
    );
    
    String budgetType = job['budget_type'] ?? 'fixed';
    String? category = job['category'];
    String? experienceLevel = job['experience_level'];
    String status = job['status'] ?? 'active';
    bool isSaving = false;
    
    final categories = [
      'Construction', 'Cleaning', 'Plumbing', 'Electrical', 'Carpentry',
      'Painting', 'Gardening', 'Welding', 'Masonry', 'Roofing',
      'General Labor', 'Other',
    ];
    final budgetTypes = ['fixed', 'hourly', 'daily', 'weekly'];
    final experienceLevels = ['beginner', 'intermediate', 'expert'];
    final statuses = ['active', 'in_progress', 'completed', 'cancelled'];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: JobsyColors.surfaceLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: JobsyColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF14141C),
                          Color(0xFF1A1A2E),
                          Color(0xFF0E0E14),
                        ],
                        stops: [0.0, 0.55, 1.0],
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 0.7,
                                  ),
                                ),
                                child: const Icon(Icons.edit_rounded,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) => const LinearGradient(
                                        colors: [
                                          Color(0xFFFFFFFF),
                                          Color(0xFFCBD5E1),
                                          Color(0xFFFFFFFF),
                                        ],
                                        stops: [0.0, 0.5, 1.0],
                                      ).createShader(bounds),
                                      child: const Text(
                                        'Edit Job',
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Update your job listing details',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white.withOpacity(0.75),
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Form
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Title
                      _editField(
                        controller: titleController,
                        label: 'Job Title',
                        icon: Icons.work_outline,
                      ),
                      const SizedBox(height: 16),
                      
                      // Category
                      _editDropdown(
                        label: 'Category',
                        value: category,
                        items: categories,
                        icon: Icons.category_outlined,
                        onChanged: (v) => setSheetState(() => category = v),
                      ),
                      const SizedBox(height: 16),
                      
                      // Description
                      _editField(
                        controller: descController,
                        label: 'Description',
                        icon: Icons.description_outlined,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 16),
                      
                      // Location
                      _editField(
                        controller: locationController,
                        label: 'Location',
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 16),
                      
                      // Budget type
                      const Text('Budget Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: budgetTypes.map((type) {
                          final isSelected = budgetType == type;
                          return GestureDetector(
                            onTap: () => setSheetState(() => budgetType = type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? JobsyColors.employerPrimary.withOpacity(0.1)
                                    : JobsyColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? JobsyColors.employerPrimary : JobsyColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                type[0].toUpperCase() + type.substring(1),
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? JobsyColors.employerPrimary : JobsyColors.textPrimary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      
                      // Budget amount
                      _editField(
                        controller: budgetController,
                        label: 'Budget Amount (BWP)',
                        icon: Icons.payments_outlined,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        prefix: 'P ',
                      ),
                      const SizedBox(height: 16),
                      
                      // Experience level
                      _editDropdown(
                        label: 'Experience Level',
                        value: experienceLevel,
                        items: experienceLevels,
                        icon: Icons.star_outline,
                        onChanged: (v) => setSheetState(() => experienceLevel = v),
                      ),
                      const SizedBox(height: 16),
                      
                      // Duration
                      _editField(
                        controller: durationController,
                        label: 'Duration (days)',
                        icon: Icons.timelapse_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      
                      // Status
                      _editDropdown(
                        label: 'Job Status',
                        value: status,
                        items: statuses,
                        icon: Icons.flag_outlined,
                        onChanged: (v) => setSheetState(() { if (v != null) status = v; }),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : () async {
                            // Validate
                            if (titleController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Title is required'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            if (budgetController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Budget is required'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            final budgetVal = double.tryParse(budgetController.text.trim());
                            if (budgetVal == null || budgetVal <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Enter a valid budget amount'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            
                            setSheetState(() => isSaving = true);
                            
                            try {
                              final newLocation = locationController.text.trim();
                              final locationChanged =
                                  newLocation != (job['location'] ?? '').toString().trim();
                              final updates = <String, dynamic>{
                                'title': titleController.text.trim(),
                                'description': descController.text.trim(),
                                'location': newLocation,
                                'category': category,
                                'budget_type': budgetType,
                                'budget_amount': budgetVal,
                                'experience_level': experienceLevel,
                                'status': status,
                              };
                              if (locationChanged) {
                                updates['latitude'] = null;
                                updates['longitude'] = null;
                              }
                              
                              if (durationController.text.trim().isNotEmpty) {
                                final dur = int.tryParse(durationController.text.trim());
                                if (dur != null && dur > 0) {
                                  updates['duration_days'] = dur;
                                }
                              } else {
                                updates['duration_days'] = null;
                              }
                              
                              await Supabase.instance.client
                                  .from('jobs')
                                  .update(updates)
                                  .eq('id', job['id']);
                              
                              if (mounted) {
                                Navigator.pop(ctx);
                                _loadStats();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(Icons.check_circle, color: JobsyColors.surfaceLight, size: 20),
                                        SizedBox(width: 8),
                                        Text('Job updated successfully'),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() => isSaving = false);
                              if (mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content: Text(friendlyErrorMessage(e)),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          icon: isSaving
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(color: JobsyColors.employerOnAccent, strokeWidth: 2))
                              : const Icon(Icons.save),
                          label: Text(isSaving ? 'Saving...' : 'Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JobsyColors.employerPrimary,
                            foregroundColor: JobsyColors.employerOnAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
  
  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? prefix,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: EdgeInsets.only(top: maxLines > 1 ? 14 : 0),
          child: Align(
            alignment: maxLines > 1 ? Alignment.topCenter : Alignment.center,
            widthFactor: 1.0,
            child: Icon(icon, color: JobsyColors.employerPrimary),
          ),
        ),
        prefixIconConstraints: maxLines > 1
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        prefixText: prefix,
        prefixStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold, color: JobsyColors.employerPrimary,
        ),
        filled: true,
        fillColor: JobsyColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: JobsyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JobsyColors.employerPrimary, width: 2),
        ),
      ),
    );
  }
  
  Widget _editDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    // Ensure value exists in items, otherwise set to null
    final safeValue = (value != null && items.contains(value)) ? value : null;
    return DropdownButtonFormField<String>(
      value: safeValue,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: JobsyColors.employerPrimary),
        filled: true,
        fillColor: JobsyColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: JobsyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JobsyColors.employerPrimary, width: 2),
        ),
      ),
      items: items.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item[0].toUpperCase() + item.substring(1)),
      )).toList(),
      onChanged: onChanged,
    );
  }
  
  Widget _buildWalletTab() {
    return const JobsyComingSoon(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Wallet Coming Soon',
      subtitle: 'Secure in-app payments are on the way. For now, post jobs and message workers — completely free.',
      note: 'Every other part of Jobsy works without a wallet. We\'ll notify you the moment payments go live.',
      accentGradient: JobsyColors.employerGradient,
    );
  }

  void _showCoverOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: JobsyColors.employerPrimary),
              title: const Text('Take Cover Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickCoverImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: JobsyColors.employerPrimary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickCoverImage(ImageSource.gallery);
              },
            ),
            if (_coverUrl != null && _coverUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Cover', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeCover();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCoverImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 900,
        imageQuality: 85,
      );
      if (image == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: JobsyColors.employerPrimary),
        ),
      );

      await ProfileImageService.uploadCover(image);
      await _loadUserProfile();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover photo updated!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeCover() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: JobsyColors.employerPrimary),
        ),
      );

      await ProfileImageService.removeCover();
      await _loadUserProfile();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover photo removed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: JobsyColors.employerPrimary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: JobsyColors.employerPrimary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: JobsyColors.employerPrimary),
        ),
      );

      await ProfileImageService.uploadAvatar(image);
      await _loadUserProfile();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removePhoto() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: JobsyColors.employerPrimary),
        ),
      );

      await ProfileImageService.removeAvatar();
      await _loadUserProfile();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo removed!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Widget _buildNotificationsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: JobsyColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Notifications',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: JobsyColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(fontSize: 16, color: JobsyColors.textTertiary),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMessagesTab() {
    return Column(
      children: [
        // Cinematic gradient header with glow orb
        ClipRect(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF14141C),
                  Color(0xFF1A1A2E),
                  Color(0xFF0E0E14),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 150,
                    height: 150,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 0.7,
                          ),
                        ),
                        child: const Icon(Icons.forum_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFCBD5E1),
                                  Color(0xFFFFFFFF),
                                ],
                                stops: [0.0, 0.5, 1.0],
                              ).createShader(bounds),
                              child: const Text(
                                'Messages',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Chat with workers about your jobs',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withOpacity(0.75),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: ConversationsListScreen(isEmployer: true),
        ),
      ],
    );
  }
  
  
  Widget _buildProfileTab() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ProfileCoverHeader(
              coverUrl: _coverUrl,
              fallbackGradient: JobsyColors.employerCoverGradient,
              onEditCover: _showCoverOptions,
              child: ProfileHeaderBody(
                  children: [
                    ProfileHeaderAvatar(
                      avatarUrl: _avatarUrl,
                      fallbackLetter: _userName.isNotEmpty ? _userName : 'E',
                      badgeGradient: JobsyColors.employerGradient,
                      onTap: _showPhotoOptions,
                    ),
                    const SizedBox(height: 20),
                    // Metallic shader name
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFFFFFF),
                          Color(0xFFCBD5E1),
                          Color(0xFFFFFFFF),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ).createShader(bounds),
                      child: Text(
                        _userName.isNotEmpty ? _userName : '\u00A0',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_companyName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _companyName,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_businessType.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 0.7,
                          ),
                        ),
                        child: Text(
                          _businessType,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                    if (!_isLoading && _profileRating != null && _profileRating! > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ...List.generate(5, (i) {
                            final n = _profileRating!.round().clamp(0, 5);
                            return Icon(
                              i < n ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: const Color(0xFFF59E0B),
                              size: 22,
                            );
                          }),
                          const SizedBox(width: 8),
                          Text(
                            _profileRating!.toStringAsFixed(1),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Average from workers',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withOpacity(0.65),
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ] else if (!_isLoading) ...[
                      const SizedBox(height: 10),
                      Text(
                        'No ratings yet — workers rate you after jobs',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.65),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      Supabase.instance.client.auth.currentUser?.email ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
        
        const SizedBox(height: 8),
        
        // Settings Options
        _buildSettingsSection(
          title: 'Account',
          items: [
            _buildSettingsTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch to Worker',
              subtitle: 'Browse jobs and apply for work',
              onTap: _switchRole,
            ),
            _buildSettingsTile(
              icon: Icons.person_outline,
              title: 'My Info',
              onTap: () => _showEditProfileDialog(),
            ),
            _buildSettingsTile(
              icon: Icons.account_balance_wallet,
              title: 'Wallet',
              onTap: () => setState(() => _selectedIndex = 2),
            ),
          ],
        ),
        
        _buildSettingsSection(
          title: 'Preferences',
          items: [
            _buildSettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: _notificationsEnabled ? 'All notifications on' : 'All notifications off',
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: (val) {
                  _toggleNotifications(val);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? 'Notifications enabled' : 'Notifications disabled'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: JobsyColors.employerPrimary,
              ),
            ),
            _buildSettingsTile(
              icon: Icons.message_outlined,
              title: 'Message Alerts',
              subtitle: _messageAlertsEnabled ? 'Message sounds on' : 'Message sounds off',
              trailing: Switch(
                value: _messageAlertsEnabled,
                onChanged: (val) {
                  _toggleMessageAlerts(val);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? 'Message alerts enabled' : 'Message alerts disabled'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: JobsyColors.employerPrimary,
              ),
            ),
            _buildSettingsTile(
              icon: Icons.language,
              title: 'Language',
              subtitle: _selectedLanguage,
              onTap: _showLanguageDialog,
            ),
          ],
        ),
        
        _buildSettingsSection(
          title: 'Support',
          items: [
            _buildSettingsTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'App tour',
              subtitle: 'Replay the interactive onboarding',
              onTap: () => OnboardingTutorialService.replay(
                context,
                AppConstants.userTypeEmployer,
              ),
            ),
            _buildSettingsTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          JobsyDialogHeader(
                            icon: Icons.support_agent,
                            title: 'Help & Support',
                            subtitle: 'We\'re here to help you!',
                            accentColor: JobsyColors.employerPrimary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          
                          // Content
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSupportOption(
                                  icon: Icons.email_outlined,
                                  title: 'Email Support',
                                  subtitle: 'futurifydesigns@gmail.com',
                                  color: const Color(0xFF3B82F6),
                                  onTap: () => _launchSupportUrl(
                                    'mailto:futurifydesigns@gmail.com?subject=Jobsy%20Support',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildSupportOption(
                                  icon: Icons.phone_outlined,
                                  title: 'Phone Support',
                                  subtitle: '+267 77036545',
                                  color: const Color(0xFF10B981),
                                  onTap: () => _launchSupportUrl('tel:+26777036545'),
                                ),
                                const SizedBox(height: 12),
                                _buildSupportOption(
                                  icon: Icons.chat_bubble_outline,
                                  title: 'WhatsApp',
                                  subtitle: '+267 77036545',
                                  color: const Color(0xFF14B8A6),
                                  onTap: () => _launchSupportUrl('https://wa.me/26777036545'),
                                ),
                                const SizedBox(height: 24),
                                const Divider(),
                                const SizedBox(height: 16),
                                Text(
                                  'Common Questions',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: JobsyColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildFaqItem('How do I post a job?', 'Go to Home tab and tap "Post a Job" button'),
                                _buildFaqItem('How do payments work?', 'For now, arrange payment directly with your worker. In-app payments are coming soon.'),
                                _buildFaqItem('Is Jobsy free?', 'Yes — posting and messaging are completely free while we finish the wallet.'),
                              ],
                            ),
                          ),
                          
                          // Footer
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: JobsyColors.employerFilledButtonStyle(padding: const EdgeInsets.symmetric(vertical: 16), radius: 12),
                                child: const Text('Close', style: TextStyle(fontSize: 16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            _buildSettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy & Security',
              onTap: _showPrivacyAndDataSheet,
            ),
            _buildSettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              onTap: () => PrivacyConsentService.openTerms(),
            ),
            _buildSettingsTile(
              icon: Icons.cookie_outlined,
              title: 'Cookie / analytics preference',
              onTap: _showAnalyticsConsentSheet,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
          child: AnimatedPressButton(
            scaleDown: 0.98,
            onPressed: _handleSignOut,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    JobsyColors.error.withOpacity(0.15),
                    JobsyColors.error.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: JobsyColors.error.withOpacity(0.4),
                  width: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: JobsyColors.error.withOpacity(0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.logout_rounded,
                    color: JobsyColors.error,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.error,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // App Version
        Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Text(
              'Jobsy App v1.0.0\nBuilt by Futurify Designs',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: JobsyColors.textTertiary.withOpacity(0.8),
                height: 1.6,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSettingsSection({
    required String title,
    required List<Widget> items,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: JobsyColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  JobsyColors.surfaceLight,
                  JobsyColors.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: JobsyColors.border.withOpacity(0.5),
                width: 0.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: _intersperseDividers(items),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _intersperseDividers(List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: JobsyColors.border.withOpacity(0.4),
            ),
          ),
        );
      }
    }
    return result;
  }
  
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: JobsyColors.employerPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: JobsyColors.employerPrimary.withOpacity(0.25),
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  icon,
                  color: JobsyColors.employerPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: JobsyColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: JobsyColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: JobsyColors.textTertiary,
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSupportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.18),
                color.withOpacity(0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3), width: 0.7),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: JobsyColors.textPrimary,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: JobsyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: color.withOpacity(0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFaqItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JobsyColors.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: JobsyColors.border.withOpacity(0.4),
          width: 0.6,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          listTileTheme: const ListTileThemeData(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: JobsyColors.employerPrimary,
          collapsedIconColor: JobsyColors.textTertiary,
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: JobsyColors.employerPrimary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              size: 14,
              color: JobsyColors.employerPrimary,
            ),
          ),
          title: Text(
            question,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: JobsyColors.textPrimary,
              letterSpacing: 0.1,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                answer,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: JobsyColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _showPrivacyAndDataSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JobsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Privacy & data protection',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Jobsy processes personal data under Botswana\'s ${AppConstants.dataProtectionAct}. '
                'You can access, correct, or request erasure of your data by emailing ${AppConstants.supportEmail}.',
                style: const TextStyle(fontSize: 14, height: 1.45, color: JobsyColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Open Privacy Policy'),
                onTap: () {
                  Navigator.pop(ctx);
                  PrivacyConsentService.openPrivacyPolicy();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cookie_outlined),
                title: const Text('Open Cookie Policy'),
                onTap: () {
                  Navigator.pop(ctx);
                  PrivacyConsentService.openCookies();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Optional analytics preference'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAnalyticsConsentSheet();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAnalyticsConsentSheet() async {
    final current = await PrivacyConsentService.read();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JobsyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Optional analytics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                current == null
                    ? 'Choose whether Jobsy may use optional analytics to improve the app. Essential features always work.'
                    : current
                        ? 'Optional analytics are currently enabled.'
                        : 'Optional analytics are currently declined.',
                style: const TextStyle(fontSize: 14, height: 1.45, color: JobsyColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: JobsyColors.employerFilledButtonStyle(radius: 12),
                  onPressed: () async {
                    await PrivacyConsentService.setAccepted(true);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Analytics enabled.')),
                    );
                  },
                  child: const Text('Enable'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await PrivacyConsentService.setAccepted(false);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Analytics declined. Only essential processing continues.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrivacySection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JobsyColors.employerPrimary.withOpacity(0.10),
            JobsyColors.employerPrimary.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JobsyColors.employerPrimary.withOpacity(0.2),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: JobsyColors.employerGradient,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: JobsyColors.employerPrimary.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 14, color: JobsyColors.employerOnAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: JobsyColors.employerGradient,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: JobsyColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
  
  Widget _buildTermsSection({
    required String number,
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JobsyColors.inputBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JobsyColors.border.withOpacity(0.4),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: JobsyColors.employerGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: JobsyColors.employerPrimary.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: JobsyColors.employerOnAccent,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: JobsyColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Language picker dialog — English + Setswana
  void _showLanguageDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  JobsyColors.surfaceLight,
                  JobsyColors.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: JobsyColors.employerPrimary.withOpacity(0.15),
                width: 0.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: JobsyColors.employerPrimary.withOpacity(0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const JobsyDialogHeader(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  subtitle: 'Choose your preferred language',
                  accentColor: JobsyColors.employerPrimary,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    children: [
                      _buildLanguageOption(
                        flag: '🇬🇧',
                        name: 'English',
                        native: 'English',
                        selected: _selectedLanguage == 'English',
                        ready: true,
                        onTap: () {
                          setState(() => _selectedLanguage = 'English');
                          _saveLanguagePref('English');
                          setDialogState(() {});
                          Navigator.pop(ctx);
                        },
                      ),
                      const SizedBox(height: 12),
                      // Additional languages coming soon
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: JobsyColors.inputBackground.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: JobsyColors.border.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 20,
                              color: JobsyColors.textTertiary.withOpacity(0.7),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'More languages coming soon',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: JobsyColors.textTertiary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
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
  
  Widget _buildLanguageOption({
    required String flag,
    required String name,
    required String native,
    required bool selected,
    required bool ready,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      JobsyColors.employerPrimary.withOpacity(0.2),
                      JobsyColors.employerPrimary.withOpacity(0.08),
                    ],
                  )
                : null,
            color: selected ? null : JobsyColors.inputBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? JobsyColors.employerPrimary.withOpacity(0.5)
                  : JobsyColors.border.withOpacity(0.4),
              width: selected ? 1 : 0.6,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: JobsyColors.employerPrimary.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: JobsyColors.textPrimary,
                            letterSpacing: 0.1,
                          ),
                        ),
                        if (!ready) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: JobsyColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: JobsyColors.warning.withOpacity(0.4),
                                width: 0.5,
                              ),
                            ),
                            child: const Text(
                              'BETA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: JobsyColors.warning,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      native,
                      style: const TextStyle(
                        fontSize: 12,
                        color: JobsyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: JobsyColors.employerGradient,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: JobsyColors.employerOnAccent,
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Safe URL launcher for support options
  Future<void> _launchSupportUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not open that link.'),
              backgroundColor: JobsyColors.error,
            ),
          );
        }
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
}
