import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../config/colors.dart';
import '../../config/routes.dart';
import '../../services/job_matching_service.dart';
import '../../utils/location_helper.dart';
import '../../widgets/modern_widgets.dart';
import '../../widgets/notifications_bell.dart';
import '../../config/page_transitions.dart';
import '../../services/push_notification_service.dart';
import '../../services/messaging_service.dart';
import '../../services/new_rating_popup_service.dart';
import '../../utils/error_messages.dart';
import '../../services/onboarding_tutorial_service.dart';
import '../../services/privacy_consent_service.dart';
import '../../services/role_service.dart';
import '../../widgets/role_setup_prompt.dart';
import '../../services/profile_image_service.dart';
import '../../utils/profile_rating.dart';
import '../../widgets/profile_cover_header.dart';
import '../../widgets/profile_header_avatar.dart';
import '../../widgets/jobsy_app_shell.dart';
import '../../widgets/rating_dialog.dart';
import '../../config/constants.dart';
import 'job_browse_screen.dart';
import 'job_details_screen.dart';
import '../chat/conversations_list_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});
  
  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _userName = '';
  String _bio = '';
  String _experienceLevel = '';
  List<String> _skills = [];
  double _hourlyRate = 0;
  String? _avatarUrl;
  String? _coverUrl;
  /// Average star rating from `profiles.rating` (employers who rated this worker).
  double? _profileRating;
  RealtimeChannel? _workerProfileChannel;
  bool _isLoading = true;
  int _unreadMessagesCount = 0;
  int _activeJobsCount = 0;
  
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
          role: AppConstants.userTypeWorker,
        );
      });
    }
  }

  Future<void> _switchRole() async {
    await RoleService.confirmAndSwitch(
      context,
      targetRole: AppConstants.userTypeEmployer,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
    _loadLanguagePref();
    _loadNotificationPrefs();
    _loadBadgeCounts();
    _subscribeWorkerProfileRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(NewRatingPopupService.check(context, isEmployer: false));
      unawaited(OnboardingTutorialService.maybeShow(context));
    });
  }

  void _subscribeWorkerProfileRealtime() {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    _workerProfileChannel?.unsubscribe();
    _workerProfileChannel = Supabase.instance.client
        .channel('worker-profile-live-$myId')
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
    _workerProfileChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUserProfile();
      _loadBadgeCounts();
      unawaited(NewRatingPopupService.check(context, isEmployer: false));
    }
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

  Future<void> _loadBadgeCounts() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Count unread messages
      final conversations = await Supabase.instance.client
          .from('conversations')
          .select('worker_unread_count')
          .eq('worker_id', userId)
          .eq('inbox_visible', true);
      int totalUnread = 0;
      for (final c in (conversations as List)) {
        totalUnread += (c['worker_unread_count'] as int? ?? 0);
      }

      // Count active/accepted jobs
      final activeJobs = await Supabase.instance.client
          .from('job_applications')
          .select('id')
          .eq('worker_id', userId)
          .inFilter('status', ['accepted', 'pending']);
      
      if (mounted) {
        setState(() {
          _unreadMessagesCount = totalUnread;
          _activeJobsCount = (activeJobs as List).length;
        });
      }
    } catch (e) {
      debugPrint('Load badge counts error: $e');
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
          'full_name, bio, experience_level, skills, hourly_rate, phone, location, avatar_url, cover_url, rating';
      const withoutCover =
          'full_name, bio, experience_level, skills, hourly_rate, phone, location, avatar_url, rating';
      const baseSelect =
          'full_name, bio, experience_level, skills, hourly_rate, phone, location, rating';

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
          _bio = response['bio'] ?? '';
          _experienceLevel = response['experience_level'] ?? '';
          _skills = response['skills'] != null
              ? List<String>.from(response['skills'])
              : [];
          _hourlyRate = response['hourly_rate'] != null
              ? (response['hourly_rate'] as num).toDouble()
              : 0.0;
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
  
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) _loadBadgeCounts();
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
      final bioController = TextEditingController(text: profileData['bio'] ?? '');
      final hourlyRateController = TextEditingController(
        text: profileData['hourly_rate']?.toString() ?? ''
      );
      String? selectedExperience = profileData['experience_level'];
      List<String> selectedSkills = List<String>.from(profileData['skills'] ?? []);
      
      final experienceLevels = ['beginner', 'intermediate', 'expert'];
      final availableSkills = [
        'Plumbing', 'Electrical', 'Carpentry', 'Painting', 
        'Welding', 'Masonry', 'Roofing', 'Cleaning', 'Gardening', 'Other'
      ];
      
      final otherSkillController = TextEditingController();
      bool showOtherSkillField = selectedSkills.any((s) => !availableSkills.contains(s) || s == 'Other');
      if (showOtherSkillField && selectedSkills.isNotEmpty) {
        // Pre-fill custom skills
        final customSkills = selectedSkills.where((s) => !availableSkills.contains(s) || s == 'Other').toList();
        if (customSkills.isNotEmpty && customSkills.first != 'Other') {
          otherSkillController.text = customSkills.join(', ');
        }
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
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
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
                  color: JobsyColors.workerPrimary.withOpacity(0.15),
                  width: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: JobsyColors.workerPrimary.withOpacity(0.12),
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
                    subtitle: 'Update your worker profile',
                    accentColor: JobsyColors.workerPrimary,
                  ),
                  // Scrollable content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Personal section
                          _buildWorkerDialogSectionLabel('Personal', Icons.person_outline_rounded),
                          const SizedBox(height: 14),
                          JobsyTextField(
                            controller: nameController,
                            label: 'Full Name',
                            hint: 'Your full name',
                            prefixIcon: Icons.person_rounded,
                            accentColor: JobsyColors.workerPrimary,
                          ),
                          const SizedBox(height: 16),
                          JobsyTextField(
                            controller: bioController,
                            label: 'Bio',
                            hint: 'Tell employers about yourself...',
                            prefixIcon: Icons.description_rounded,
                            maxLines: 3,
                            accentColor: JobsyColors.workerPrimary,
                          ),
                          const SizedBox(height: 16),
                          JobsyTextField(
                            controller: phoneController,
                            label: 'Phone Number',
                            hint: '+267 XX XXX XXX',
                            prefixIcon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                            accentColor: JobsyColors.workerPrimary,
                          ),
                          const SizedBox(height: 16),
                          JobsyTextField(
                            controller: locationController,
                            label: 'Location',
                            hint: 'City or area',
                            prefixIcon: Icons.location_on_rounded,
                            accentColor: JobsyColors.workerPrimary,
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
                          // Work section
                          _buildWorkerDialogSectionLabel('Work Profile', Icons.work_outline_rounded),
                          const SizedBox(height: 14),
                          JobsyTextField(
                            controller: hourlyRateController,
                            label: 'Hourly Rate (Pula)',
                            hint: 'e.g. 50',
                            prefixIcon: Icons.payments_rounded,
                            keyboardType: TextInputType.number,
                            accentColor: JobsyColors.workerPrimary,
                          ),
                          const SizedBox(height: 16),
                          _buildWorkerDialogDropdown(
                            label: 'Experience Level',
                            value: selectedExperience,
                            items: experienceLevels,
                            icon: Icons.star_rounded,
                            onChanged: (value) {
                              setDialogState(() => selectedExperience = value);
                            },
                          ),
                          const SizedBox(height: 22),
                          // Skills label with icon pill
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.construction_rounded,
                                  size: 16,
                                  color: JobsyColors.workerPrimary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Skills',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: JobsyColors.textSecondary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '(${selectedSkills.length} selected)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: JobsyColors.textTertiary.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Skill chips — custom styled for dark theme
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableSkills.map((skill) {
                              final isSelected = selectedSkills.contains(skill) ||
                                  (skill == 'Other' && selectedSkills.any((s) => !availableSkills.contains(s)));
                              return _buildSkillChip(
                                label: skill,
                                selected: isSelected,
                                onTap: () {
                                  setDialogState(() {
                                    if (skill == 'Other') {
                                      showOtherSkillField = !isSelected;
                                      if (!showOtherSkillField) {
                                        selectedSkills.removeWhere((s) => !availableSkills.contains(s) || s == 'Other');
                                        otherSkillController.clear();
                                      }
                                    } else {
                                      if (isSelected) {
                                        selectedSkills.remove(skill);
                                      } else {
                                        selectedSkills.add(skill);
                                      }
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          if (showOtherSkillField) ...[
                            const SizedBox(height: 16),
                            JobsyTextField(
                              controller: otherSkillController,
                              label: 'Specify Other Skills',
                              hint: 'e.g. Photography, Tutoring',
                              prefixIcon: Icons.add_circle_outline_rounded,
                              maxLines: 2,
                              accentColor: JobsyColors.workerPrimary,
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 4, top: 6),
                              child: Text(
                                'Separate multiple skills with commas',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: JobsyColors.textTertiary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
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
                            gradient: JobsyColors.workerGradient,
                            height: 48,
                            fontSize: 14,
                            onPressed: () async {
                              try {
                                final userId = Supabase.instance.client.auth.currentUser?.id;
                                
                                // Process skills - handle custom "Other" skills
                                List<String> finalSkills = [...selectedSkills];
                                if (showOtherSkillField && otherSkillController.text.trim().isNotEmpty) {
                                  // Remove 'Other' placeholder if exists
                                  finalSkills.removeWhere((s) => s == 'Other' || !availableSkills.contains(s));
                                  // Add custom skills (split by comma and trim)
                                  final customSkills = otherSkillController.text
                                      .split(',')
                                      .map((s) => s.trim())
                                      .where((s) => s.isNotEmpty)
                                      .toList();
                                  finalSkills.addAll(customSkills);
                                }
                                
                                final updateData = {
                                  if (nameController.text.trim().isNotEmpty)
                                    'full_name': nameController.text.trim(),
                                  if (bioController.text.trim().isNotEmpty)
                                    'bio': bioController.text.trim(),
                                  if (hourlyRateController.text.trim().isNotEmpty)
                                    'hourly_rate': double.tryParse(hourlyRateController.text),
                                  if (selectedExperience != null)
                                    'experience_level': selectedExperience,
                                  'skills': finalSkills,
                                  if (phoneController.text.trim().isNotEmpty)
                                    'phone': phoneController.text.trim(),
                                  if (locationController.text.trim().isNotEmpty)
                                    'location': locationController.text.trim(),
                                };
                                
                                debugPrint('Saving profile data: $updateData');
                                
                                await Supabase.instance.client
                                    .from('profiles')
                                    .update(updateData)
                                    .eq('id', userId!);
                                
                                debugPrint('Profile saved successfully');
                                
                                await _loadUserProfile();
                                
                                debugPrint('Profile reloaded after save');
                                
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: const [
                                        Icon(Icons.check_circle, color: Colors.white),
                                        SizedBox(width: 12),
                                        Text('Profile updated successfully!'),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              } catch (e) {
                                debugPrint('Error saving profile: $e');
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(friendlyErrorMessage(e)),
                                    backgroundColor: Colors.red,
                                  ),
                                );
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
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }
  
  // Dark-themed section label for worker dialogs
  Widget _buildWorkerDialogSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: JobsyColors.workerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: JobsyColors.workerPrimary.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: JobsyColors.workerOnAccent, size: 14),
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
  
  // Dark-themed dropdown for worker dialogs
  Widget _buildWorkerDialogDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
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
            dropdownColor: JobsyColors.surfaceElevated,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: JobsyColors.workerPrimary.withOpacity(0.8),
            ),
            style: const TextStyle(
              fontSize: 16,
              color: JobsyColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: JobsyColors.workerPrimary.withOpacity(0.8),
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
                  // Capitalize first letter for nicer display
                  type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type,
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
  
  // Selectable chip for skills — gradient when selected, subtle when not
  Widget _buildSkillChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: JobsyColors.workerGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : JobsyColors.inputBackground,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : JobsyColors.border.withOpacity(0.5),
              width: 0.7,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: JobsyColors.workerPrimary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, color: JobsyColors.workerOnAccent, size: 14),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? JobsyColors.workerOnAccent : JobsyColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              accentColor: JobsyColors.workerPrimary,
              isEmployer: false,
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
                  _buildFindJobsTab(),
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
        accentColor: JobsyColors.workerPrimary,
        items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.search),
              activeIcon: Icon(Icons.search),
              label: 'Find Jobs',
            ),
            BottomNavigationBarItem(
              icon: _activeJobsCount > 0
                  ? Badge(
                      label: Text(_activeJobsCount > 9 ? '9+' : '$_activeJobsCount',
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
  
  Widget _buildFindJobsTab() {
    return const JobBrowseScreen();
  }
  
  Widget _buildMyJobsTab() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    return FutureBuilder<Map<String, int>>(
      future: _getJobCounts(userId),
      builder: (context, snapshot) {
        final activeCount = snapshot.data?['active'] ?? 0;
        final pastCount = snapshot.data?['past'] ?? 0;
        
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
                        JobsyColors.workerPrimary,
                        JobsyColors.workerDark,
                        Color(0xFF1A1A2E),
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
                                      'Track your accepted & completed work',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white.withOpacity(0.75),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
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
                              labelColor: JobsyColors.workerOnAccent,
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
                                Tab(text: 'Active ($activeCount)'),
                                Tab(text: 'Past ($pastCount)'),
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
      },
    );
  }
  
  Future<Map<String, int>> _getJobCounts(String? userId) async {
    if (userId == null) {
      return {'active': 0, 'past': 0};
    }
    
    try {
      final applications = await Supabase.instance.client
          .from('job_applications')
          .select('status')
          .eq('worker_id', userId);
      
      final activeCount = applications
          .where((app) => app['status'] == 'accepted' || app['status'] == 'in_progress')
          .length;
      
      final pastCount = applications
          .where((app) {
            final s = app['status'] as String?;
            return s == 'completed' ||
                s == 'withdrawn' ||
                s == 'cancelled';
          })
          .length;
      
      return {'active': activeCount, 'past': pastCount};
    } catch (e) {
      debugPrint('Error getting job counts: $e');
      return {'active': 0, 'past': 0};
    }
  }
  
  Widget _buildActiveJobsList() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    if (userId == null) {
      return const Center(child: Text('Please log in to view your jobs'));
    }
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('job_applications')
          .stream(primaryKey: ['id'])
          .eq('worker_id', userId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
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
          return const Center(child: CircularProgressIndicator(color: JobsyColors.workerPrimary));
        }
        
        // Filter for active statuses (accepted, in_progress)
        final activeApplications = snapshot.data!
            .where((app) => app['status'] == 'accepted' || app['status'] == 'in_progress')
            .toList();
        
        if (activeApplications.isEmpty) {
          return Center(
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
                      color: JobsyColors.workerPrimary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.work_outline_rounded,
                    size: 42,
                    color: JobsyColors.workerPrimary,
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
                  'Applied jobs will appear here',
                  style: TextStyle(fontSize: 14, color: JobsyColors.textTertiary),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          itemCount: activeApplications.length,
          itemBuilder: (context, index) {
            final application = activeApplications[index];
            return FutureBuilder<Map<String, dynamic>?>(
              future: _loadJobDetailsSafe(application['job_id'] as String),
              builder: (context, jobSnapshot) {
                if (jobSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: JobsyColors.workerPrimary)),
                  );
                }
                if (jobSnapshot.hasError) {
                  return _buildWorkerJobLoadError(
                      'Could not load this job. Pull down to refresh.');
                }
                final job = jobSnapshot.data;
                if (job == null) {
                  return _buildWorkerJobLoadError(
                      'This job is no longer available or you can\'t view it.');
                }
                final employer = job['employer'] as Map<String, dynamic>?;

                return AnimatedListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildWorkerJobCard(
                      title: job['title'] ?? 'Untitled Job',
                      employer: employer?['full_name'] ?? 'Anonymous',
                      employerAvatar: employer?['avatar_url'],
                      employerId: job['employer_id'] as String?,
                      price: 'P${job['budget_amount']}',
                      location: job['location'] ?? 'Location not specified',
                      status: application['status'] == 'accepted' ? 'Accepted' : 'In Progress',
                      statusColor: application['status'] == 'accepted'
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                      date: job['created_at']?.substring(0, 10) ?? '',
                      jobId: job['id'],
                      applicationId: application['id'],
                      onWithdraw: () => _confirmWithdrawFromJob(
                        jobTitle: job['title'] as String? ?? 'Job',
                        applicationId: application['id'] as String,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  Future<Map<String, dynamic>?> _loadJobDetailsSafe(String jobId) async {
    try {
      return await Supabase.instance.client
          .from('jobs')
          .select('''
            *,
            employer:profiles!employer_id (
              full_name,
              avatar_url
            )
          ''')
          .eq('id', jobId)
          .maybeSingle();
    } catch (e) {
      debugPrint('_loadJobDetailsSafe: $e');
      return null;
    }
  }

  /// Completed tab: job + employer's star rating for this worker on this job.
  Future<Map<String, dynamic>> _loadCompletedJobRow(
      String jobId, String applicationId) async {
    final job = await _loadJobDetailsSafe(jobId);
    int stars = 0;
    var workerHasRated = false;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final received = await Supabase.instance.client
            .from('ratings')
            .select('rating')
            .eq('application_id', applicationId)
            .eq('rated_id', uid)
            .maybeSingle();
        stars = (received?['rating'] as num?)?.toInt() ?? 0;

        final mine = await Supabase.instance.client
            .from('ratings')
            .select('id')
            .eq('application_id', applicationId)
            .eq('rater_id', uid)
            .maybeSingle();
        workerHasRated = mine != null;
      }
    } catch (e) {
      debugPrint('_loadCompletedJobRow rating: $e');
    }
    return {
      'job': job,
      'rating': stars,
      'workerHasRated': workerHasRated,
    };
  }

  Future<void> _rateEmployerForJob({
    required String jobTitle,
    required String employerId,
    required String employerName,
    required String jobId,
    required String applicationId,
  }) async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RatingDialog(
        jobTitle: jobTitle,
        ratedUserId: employerId,
        ratedUserName: employerName,
        jobId: jobId,
        applicationId: applicationId,
        isRatingWorker: false,
      ),
    );
    if (submitted == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your rating was submitted.')),
      );
    }
  }

  Widget _buildWorkerJobLoadError(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JobsyColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber[700], size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13.5, color: JobsyColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompletedJobsList() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    if (userId == null) {
      return const Center(child: Text('Please log in to view your jobs'));
    }
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('job_applications')
          .stream(primaryKey: ['id'])
          .eq('worker_id', userId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
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
          return const Center(child: CircularProgressIndicator(color: JobsyColors.workerPrimary));
        }
        
        // Filter for completed status
        final pastApplications = snapshot.data!
            .where((app) {
              final s = app['status'] as String?;
              return s == 'completed' ||
                  s == 'withdrawn' ||
                  s == 'cancelled';
            })
            .toList();
        
        if (pastApplications.isEmpty) {
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
                    'Finished, withdrawn, and cancelled work appears here',
                    style: TextStyle(fontSize: 14, color: JobsyColors.textTertiary),
                  ),
                ],
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          itemCount: pastApplications.length,
          itemBuilder: (context, index) {
            final application = pastApplications[index];
            return FutureBuilder<Map<String, dynamic>>(
              future: _loadCompletedJobRow(
                application['job_id'] as String,
                application['id'] as String,
              ),
              builder: (context, jobSnapshot) {
                if (jobSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: JobsyColors.workerPrimary)),
                  );
                }
                if (jobSnapshot.hasError || jobSnapshot.data == null) {
                  return _buildWorkerJobLoadError(
                      'Could not load this completed job. Try again.');
                }
                final payload = jobSnapshot.data!;
                final job = payload['job'] as Map<String, dynamic>?;
                final rating = (payload['rating'] as num?)?.toInt() ?? 0;
                final workerHasRated = payload['workerHasRated'] == true;
                if (job == null) {
                  return _buildWorkerJobLoadError(
                      'This job is no longer available or you can\'t view it.');
                }
                final employer = job['employer'] as Map<String, dynamic>?;

                final appSt = application['status'] as String?;
                String pastLabel;
                Color pastColor;
                switch (appSt) {
                  case 'withdrawn':
                    pastLabel = 'You withdrew';
                    pastColor = const Color(0xFF94A3B8);
                    break;
                  case 'cancelled':
                    pastLabel = 'Cancelled';
                    pastColor = const Color(0xFFDC2626);
                    break;
                  default:
                    pastLabel = 'Completed';
                    pastColor = const Color(0xFF10B981);
                }

                return AnimatedListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildWorkerJobCard(
                      title: job['title'] ?? 'Untitled Job',
                      employer: employer?['full_name'] ?? 'Anonymous',
                      employerAvatar: employer?['avatar_url'],
                      employerId: employer?['id']?.toString(),
                      price: 'P${job['budget_amount']}',
                      location: job['location'] ?? 'Location not specified',
                      status: pastLabel,
                      statusColor: pastColor,
                      date: job['created_at']?.substring(0, 10) ?? '',
                      rating: rating,
                      workerHasRatedEmployer: workerHasRated,
                      isCompleted: true,
                      jobId: job['id'],
                      applicationId: application['id'],
                      applicationOutcome: appSt,
                      onRateEmployer: employer?['id'] != null
                          ? () => _rateEmployerForJob(
                                jobTitle: job['title']?.toString() ?? 'Job',
                                employerId: employer!['id'].toString(),
                                employerName:
                                    employer['full_name']?.toString() ?? 'Employer',
                                jobId: job['id'].toString(),
                                applicationId: application['id'].toString(),
                              )
                          : null,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  Future<void> _confirmWithdrawFromJob({
    required String applicationId,
    required String jobTitle,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Withdraw from this job?'),
        content: Text(
          'You’ll be removed from “$jobTitle”. The employer can hire someone else.',
          style: const TextStyle(
            color: JobsyColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay on job'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Withdraw',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'worker_withdraw_from_job',
        params: {'p_application_id': applicationId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You withdrew from this job'),
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

  Widget _buildWorkerJobCard({
    required String title,
    required String employer,
    String? employerAvatar,
    String? employerId,
    required String price,
    required String location,
    required String status,
    required Color statusColor,
    required String date,
    int rating = 0,
    bool workerHasRatedEmployer = false,
    bool isCompleted = false,
    String? jobId,
    String? applicationId,
    VoidCallback? onWithdraw,
    VoidCallback? onRateEmployer,
    String? applicationOutcome,
  }) {
    final hasAvatar = employerAvatar != null && employerAvatar.isNotEmpty;
    final showActiveActions = !isCompleted &&
        employerId != null &&
        employerId.isNotEmpty &&
        applicationId != null &&
        applicationId.isNotEmpty &&
        jobId != null &&
        jobId.isNotEmpty;

    void openDetails() {
      if (jobId == null) return;
      Navigator.push(
        context,
        JobsyPageRoute(
          page: JobDetailsScreen(jobId: jobId!),
          transition: JobsyTransition.fadeSlide,
        ),
      );
    }

    return AnimatedPressButton(
      scaleDown: 0.98,
      onPressed: showActiveActions ? null : (jobId != null ? openDetails : null),
      child: Container(
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
            color: statusColor.withOpacity(0.22),
            width: 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.08),
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
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
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
                      price,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          JobsyColors.workerPrimary.withOpacity(0.4),
                          JobsyColors.workerPrimary.withOpacity(0.1),
                        ],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: JobsyColors.surfaceElevated,
                      backgroundImage: hasAvatar ? NetworkImage(employerAvatar!) : null,
                      child: !hasAvatar
                          ? Text(
                              employer.isNotEmpty ? employer[0].toUpperCase() : 'E',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: JobsyColors.workerPrimary,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      employer,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: JobsyColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: JobsyColors.workerPrimary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.location_on_rounded,
                        size: 13, color: JobsyColors.workerPrimary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 13,
                        color: JobsyColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: JobsyColors.textSecondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.calendar_today_rounded,
                        size: 12, color: JobsyColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 13,
                      color: JobsyColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (isCompleted &&
                  (applicationOutcome == 'withdrawn' ||
                      applicationOutcome == 'cancelled')) ...[
                const SizedBox(height: 8),
                Text(
                  applicationOutcome == 'withdrawn'
                      ? 'You chose to withdraw from this job.'
                      : 'The employer cancelled this job.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: JobsyColors.textTertiary.withOpacity(0.95),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ] else ...[
                if (isCompleted && rating > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Your rating: ',
                        style: TextStyle(fontSize: 13, color: JobsyColors.textTertiary),
                      ),
                      ...List.generate(5, (index) {
                        return Icon(
                          index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 18,
                          color: const Color(0xFFF59E0B),
                        );
                      }),
                    ],
                  ),
                ],
                if (isCompleted && rating == 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Employer hasn\'t left a star rating for this job yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: JobsyColors.textTertiary.withOpacity(0.9),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (isCompleted &&
                    !workerHasRatedEmployer &&
                    onRateEmployer != null &&
                    applicationOutcome != 'withdrawn' &&
                    applicationOutcome != 'cancelled') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onRateEmployer,
                      icon: const Icon(Icons.star_outline_rounded, size: 18),
                      label: Text(
                        rating > 0
                            ? 'Rate $employer back'
                            : 'Rate $employer',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JobsyColors.workerPrimary,
                        side: BorderSide(
                          color: JobsyColors.workerPrimary.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                          status,
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
                  if (showActiveActions)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: openDetails,
                          style: TextButton.styleFrom(
                            foregroundColor: JobsyColors.workerPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            'Details',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final myId =
                                Supabase.instance.client.auth.currentUser?.id;
                            if (myId == null) return;
                            MessagingService.openChat(
                              context: context,
                              applicationId: applicationId!,
                              jobId: jobId!,
                              jobTitle: title,
                              employerId: employerId!,
                              workerId: myId,
                              otherUserName: employer,
                              isEmployer: false,
                              otherUserAvatar: employerAvatar,
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: JobsyColors.workerPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                          label: const Text(
                            'Message',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    )
                  else if (jobId != null)
                    Row(
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(
                            color: JobsyColors.workerPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: JobsyColors.workerPrimary,
                        ),
                      ],
                    ),
                ],
              ),
              if (showActiveActions && onWithdraw != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onWithdraw,
                    child: const Text(
                      'Withdraw from job',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildWalletTab() {
    return const JobsyComingSoon(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Wallet Coming Soon',
      subtitle: 'Secure in-app payments and instant withdrawals are on the way. For now, apply to and message about jobs — totally free.',
      note: 'You can still use every other part of Jobsy without a wallet. We\'ll notify you the moment payments go live.',
      accentGradient: JobsyColors.workerGradient,
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
              leading: const Icon(Icons.photo_camera, color: JobsyColors.workerPrimary),
              title: const Text('Take Cover Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickCoverImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: JobsyColors.workerPrimary),
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
          child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
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
          child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
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
              leading: const Icon(Icons.photo_camera, color: JobsyColors.workerPrimary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: JobsyColors.workerPrimary),
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
          child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
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
          child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
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
                  JobsyColors.workerPrimary,
                  JobsyColors.workerDark,
                  Color(0xFF1A1A2E),
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
                              'Chat with employers about your jobs',
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
          child: ConversationsListScreen(isEmployer: false),
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
              fallbackGradient: JobsyColors.workerCoverGradient,
              onEditCover: _showCoverOptions,
              child: ProfileHeaderBody(
                  children: [
                    ProfileHeaderAvatar(
                      avatarUrl: _avatarUrl,
                      fallbackLetter: _userName.isNotEmpty ? _userName : 'W',
                      badgeGradient: JobsyColors.workerGradient,
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
                    if (!_isLoading && _userName.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Use My Info below to complete your profile',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    // Rating summary on profile card
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
                        'Average from employers',
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
                        'No ratings yet — finish jobs so employers can rate you',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.65),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_bio.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _bio,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white.withOpacity(0.85),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_experienceLevel.isNotEmpty || _hourlyRate > 0) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_experienceLevel.isNotEmpty) ...[
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
                              child: Row(
                                children: [
                                  const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    _experienceLevel[0].toUpperCase() +
                                        _experienceLevel.substring(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_experienceLevel.isNotEmpty && _hourlyRate > 0)
                            const SizedBox(width: 8),
                          if (_hourlyRate > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                                ),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                'P${_hourlyRate.toStringAsFixed(0)}/hr',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (_skills.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: _skills.take(5).map((skill) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              skill,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
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
        _buildWorkerSettingsSection(
          title: 'Account',
          items: [
            _buildWorkerSettingsTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch to Employer',
              subtitle: 'Post jobs and hire workers',
              onTap: _switchRole,
            ),
            _buildWorkerSettingsTile(
              icon: Icons.person_outline,
              title: 'My Info',
              onTap: () => _showEditProfileDialog(),
            ),
            _buildWorkerSettingsTile(
              icon: Icons.account_balance_wallet,
              title: 'Wallet',
              onTap: () => setState(() => _selectedIndex = 2),
            ),
          ],
        ),
        _buildWorkerSettingsSection(
          title: 'Preferences',
          items: [
            _buildWorkerSettingsTile(
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
                activeColor: JobsyColors.workerPrimary,
              ),
            ),
            _buildWorkerSettingsTile(
              icon: Icons.volume_up_outlined,
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
                activeColor: JobsyColors.workerPrimary,
              ),
            ),
            _buildWorkerSettingsTile(
              icon: Icons.language,
              title: 'Language',
              subtitle: _selectedLanguage,
              onTap: _showLanguageDialog,
            ),
          ],
        ),
        _buildWorkerSettingsSection(
          title: 'Support',
          items: [
            _buildWorkerSettingsTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'App tour',
              subtitle: 'Replay the interactive onboarding',
              onTap: () => OnboardingTutorialService.replay(
                context,
                AppConstants.userTypeWorker,
              ),
            ),
            _buildWorkerSettingsTile(
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
                            accentColor: JobsyColors.workerPrimary,
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
                                _buildFaqItem('How do I find jobs?', 'Browse "Find Jobs" tab, use filters, and apply to matching jobs'),
                                _buildFaqItem('How does payment work?', 'For now, payment is arranged directly with the employer. In-app payments are coming soon.'),
                                _buildFaqItem('Is Jobsy free to use?', 'Yes — posting, applying, and messaging are all free while we finish the wallet.'),
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
                                style: JobsyColors.workerFilledButtonStyle(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  radius: 12,
                                ),
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
            _buildWorkerSettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy & Security',
              onTap: _showPrivacyAndDataSheet,
            ),
            _buildWorkerSettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              onTap: () => PrivacyConsentService.openTerms(),
            ),
            _buildWorkerSettingsTile(
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
  
  Widget _buildWorkerSettingsSection({
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
                children: _intersperseWorkerDividers(items),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _intersperseWorkerDividers(List<Widget> items) {
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
  
  Widget _buildWorkerSettingsTile({
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
                  color: JobsyColors.workerPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: JobsyColors.workerPrimary.withOpacity(0.25),
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  icon,
                  color: JobsyColors.workerPrimary,
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
          iconColor: JobsyColors.workerPrimary,
          collapsedIconColor: JobsyColors.textTertiary,
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: JobsyColors.workerPrimary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              size: 14,
              color: JobsyColors.workerPrimary,
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
              Text(
                'Privacy & data protection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: JobsyColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Jobsy processes personal data under Botswana\'s ${AppConstants.dataProtectionAct}. '
                'You can access, correct, or request erasure of your data by emailing ${AppConstants.supportEmail}.',
                style: TextStyle(fontSize: 14, height: 1.45, color: JobsyColors.textSecondary),
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
                  style: JobsyColors.workerFilledButtonStyle(radius: 12),
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
                      const SnackBar(content: Text('Analytics declined. Only essential processing continues.')),
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
            JobsyColors.workerPrimary.withOpacity(0.10),
            JobsyColors.workerPrimary.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JobsyColors.workerPrimary.withOpacity(0.2),
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
                    colors: JobsyColors.workerGradient,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: JobsyColors.workerPrimary.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 14, color: JobsyColors.workerOnAccent),
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
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: JobsyColors.workerGradient,
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
                colors: JobsyColors.workerGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: JobsyColors.workerPrimary.withOpacity(0.4),
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
                  color: JobsyColors.workerOnAccent,
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
                color: JobsyColors.workerPrimary.withOpacity(0.15),
                width: 0.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: JobsyColors.workerPrimary.withOpacity(0.12),
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
                  accentColor: JobsyColors.workerPrimary,
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
                      JobsyColors.workerPrimary.withOpacity(0.2),
                      JobsyColors.workerPrimary.withOpacity(0.08),
                    ],
                  )
                : null,
            color: selected ? null : JobsyColors.inputBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? JobsyColors.workerPrimary.withOpacity(0.5)
                  : JobsyColors.border.withOpacity(0.4),
              width: selected ? 1 : 0.6,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: JobsyColors.workerPrimary.withOpacity(0.2),
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
                      colors: JobsyColors.workerGradient,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: JobsyColors.workerOnAccent,
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
