import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/colors.dart';
import '../../config/page_transitions.dart';
import '../../services/messaging_service.dart';
import '../../config/constants.dart';
import '../../services/role_service.dart';
import '../../utils/maps_launcher.dart';
import '../../utils/error_messages.dart';
import '../../widgets/role_setup_prompt.dart';
import 'job_application_form_screen.dart';

class JobDetailsScreen extends StatefulWidget {
  final String jobId;
  
  const JobDetailsScreen({super.key, required this.jobId});
  
  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  Map<String, dynamic>? _job;
  bool _isLoading = true;
  bool _isSaved = false;
  bool _hasApplied = false;
  String? _applicationStatus;
  String? _applicationId;
  bool _isApplying = false;
  bool _acceptedBannerDismissed = false;
  
  @override
  void initState() {
    super.initState();
    _loadJobDetails();
    _checkBannerDismissed();
  }
  
  Future<void> _checkBannerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'accepted_banner_seen_${widget.jobId}';
    if (prefs.getBool(key) == true) {
      if (mounted) setState(() => _acceptedBannerDismissed = true);
    }
  }
  
  Future<void> _dismissAcceptedBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accepted_banner_seen_${widget.jobId}', true);
    if (mounted) setState(() => _acceptedBannerDismissed = true);
  }
  
  Future<void> _loadJobDetails() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final jobResponse = await Supabase.instance.client
          .from('jobs')
          .select('''
            *,
            employer:profiles!employer_id (
              full_name,
              avatar_url,
              phone,
              location
            )
          ''')
          .eq('id', widget.jobId)
          .single();
      
      final savedResponse = await Supabase.instance.client
          .from('saved_jobs')
          .select()
          .eq('job_id', widget.jobId)
          .eq('worker_id', userId!)
          .maybeSingle();
      
      final applicationResponse = await Supabase.instance.client
          .from('job_applications')
          .select('id, status')
          .eq('job_id', widget.jobId)
          .eq('worker_id', userId)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _job = jobResponse;
          _isSaved = savedResponse != null;
          _hasApplied = applicationResponse != null;
          _applicationStatus = applicationResponse?['status'];
          _applicationId = applicationResponse?['id'];
          _isLoading = false;
        });
        if (_applicationStatus == 'accepted' ||
            _applicationStatus == 'in_progress') {
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _acceptedBannerDismissed = true);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading job: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }
  
  Future<void> _toggleSave() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      if (_isSaved) {
        await Supabase.instance.client
            .from('saved_jobs')
            .delete()
            .eq('job_id', widget.jobId)
            .eq('worker_id', userId);
      } else {
        await Supabase.instance.client.from('saved_jobs').insert({
          'job_id': widget.jobId,
          'worker_id': userId,
        });
      }
      if (mounted) setState(() => _isSaved = !_isSaved);
    } catch (e) {
      debugPrint('Error toggling save: $e');
    }
  }
  
  /// Normalized for Supabase/json (string, enum, or occasional casing differences).
  String? _normalizedJobStatus() {
    final raw = _job?['status'];
    if (raw == null) return null;
    final s = raw.toString().trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  Future<void> _applyToJob() async {
    if (RoleService.isOwnJobPosting(_job?['employer_id']?.toString())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot apply to your own job posting.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!await RoleService.isWorkerMode()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switch to Worker mode in your profile to apply for jobs.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!await RoleService.isWorkerProfileReadyForApply()) {
      final ready = await RoleSetupPrompt.showIfNeeded(
        context,
        role: AppConstants.userTypeWorker,
        requiredForAction: true,
      );
      if (!ready || !mounted) return;
    }

    final jobStatus = _normalizedJobStatus();
    if (jobStatus == 'in_progress') {
      final hired = _applicationStatus == 'accepted' ||
          _applicationStatus == 'in_progress';
      if (!hired) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This job is in progress with another worker. Applications open again when the listing returns to active.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    final form = await Navigator.of(context, rootNavigator: true)
        .push<JobApplicationFormResult>(
      JobsyPageRoute(
        page: JobApplicationFormScreen(
          jobTitle: _job?['title']?.toString() ?? 'Job',
        ),
        transition: JobsyTransition.slideUp,
      ),
    );
    if (form == null) return;

    setState(() => _isApplying = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final response = await Supabase.instance.client
          .from('job_applications')
          .insert({
            'job_id': widget.jobId,
            'worker_id': userId,
            'cover_letter':
                form.coverLetter.trim().isEmpty ? null : form.coverLetter.trim(),
            'references_text': form.referencesText.trim().isEmpty
                ? null
                : form.referencesText.trim(),
            'additional_info': form.additionalInfo.trim().isEmpty
                ? null
                : form.additionalInfo.trim(),
            'qualification_files': [],
            'status': 'pending',
          })
          .select()
          .single();

      final applicationId = response['id'] as String;
      final storedFiles = <Map<String, String>>[];
      final bucket = Supabase.instance.client.storage.from('application-qualifications');

      for (final file in form.qualificationFiles) {
        try {
          final bytes = await _qualificationFileBytes(file);
          if (bytes.length > 10 * 1024 * 1024) continue;
          final safeBase = _safeQualificationBaseName(file.name);
          final objectPath =
              '$applicationId/${DateTime.now().millisecondsSinceEpoch}_$safeBase';
          await bucket.uploadBinary(
            objectPath,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: _mimeForQualificationName(file.name),
              upsert: false,
            ),
          );
          storedFiles.add({'path': objectPath, 'name': file.name});
        } catch (e) {
          debugPrint('Qualification upload skipped: $e');
        }
      }

      if (storedFiles.isNotEmpty) {
        await Supabase.instance.client.from('job_applications').update({
          'qualification_files': storedFiles,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', applicationId);
      }

      if (mounted) {
        setState(() {
          _hasApplied = true;
          _applicationStatus = 'pending';
          _applicationId = applicationId;
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              form.qualificationFiles.isNotEmpty && storedFiles.length < form.qualificationFiles.length
                  ? 'Application submitted (some files could not be uploaded).'
                  : 'Application submitted!',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error applying: $e');
      if (mounted) {
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<List<int>> _qualificationFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes!;
    if (kIsWeb) {
      throw StateError('File data unavailable on web');
    }
    if (file.path != null) {
      return File(file.path!).readAsBytes();
    }
    throw StateError('No file data');
  }

  String _safeQualificationBaseName(String name) {
    final base = name.split(RegExp(r'[\\/]')).last;
    return base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _mimeForQualificationName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
  
  String _getBudgetText() {
    final amount = _job!['budget_amount'];
    final type = _job!['budget_type'];
    switch (type) {
      case 'fixed':
        return 'P$amount Fixed Price';
      case 'hourly':
        return 'P$amount per hour';
      case 'daily':
        return 'P$amount per day';
      case 'weekly':
        return 'P$amount per week';
      default:
        return 'P$amount';
    }
  }
  
  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Not specified';
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year}';
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: JobsyColors.background,
        appBar: AppBar(
          backgroundColor: JobsyColors.background,
          foregroundColor: JobsyColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
        ),
      );
    }
    
    if (_job == null) {
      return Scaffold(
        backgroundColor: JobsyColors.background,
        appBar: AppBar(
          backgroundColor: JobsyColors.background,
          foregroundColor: JobsyColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Job not found', style: TextStyle(color: JobsyColors.textSecondary)),
        ),
      );
    }
    
    final employer = _job!['employer'] as Map<String, dynamic>?;
    
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            floating: false,
            pinned: true,
            backgroundColor: JobsyColors.background,
            foregroundColor: JobsyColors.textPrimary,
            elevation: 0,
            title: const Text('Job Details',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
            actions: [
              IconButton(
                icon: Icon(_isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                color: _isSaved ? JobsyColors.workerPrimary : JobsyColors.textPrimary,
                onPressed: _toggleSave,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient backdrop
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          JobsyColors.workerDark,
                          Color(0xFF4C1D95),
                          Color(0xFF1A1A2E),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  // Soft glow orb
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 200,
                      height: 200,
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
                      padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.7),
                            ),
                            child: Text(
                              (_job!['category'] ?? '').toString().toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _job!['title'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                              height: 1.2,
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Budget + Location quick-facts
                _buildSection(
                  icon: Icons.attach_money_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Budget',
                  content: Text(
                    _getBudgetText(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    final loc = _job!['location']?.toString().trim();
                    if (loc == null || loc.isEmpty) return;
                    MapsLauncher.openJobLocation(_job!);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: _buildSection(
                    icon: Icons.location_on_rounded,
                    iconColor: JobsyColors.workerPrimary,
                    title: 'Location',
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _job!['location'] ?? 'Not specified',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: JobsyColors.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const Icon(Icons.directions_rounded,
                                size: 20, color: JobsyColors.workerPrimary),
                          ],
                        ),
                        if (MapsLauncher.hasJobCoordinates(_job!)) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Exact GPS pin — tap for directions',
                            style: TextStyle(
                              fontSize: 12,
                              color: JobsyColors.workerPrimary.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSection(
                  icon: Icons.description_outlined,
                  iconColor: JobsyColors.workerPrimary,
                  title: 'Description',
                  content: Text(
                    _job!['description'] ?? '',
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: JobsyColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ),
                if (_job!['required_skills'] != null &&
                    (_job!['required_skills'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSection(
                    icon: Icons.build_rounded,
                    iconColor: JobsyColors.workerPrimary,
                    title: 'Required Skills',
                    content: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_job!['required_skills'] as List).map((skill) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: JobsyColors.workerPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: JobsyColors.workerPrimary.withOpacity(0.25),
                              width: 0.7,
                            ),
                          ),
                          child: Text(
                            skill.toString(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: JobsyColors.workerPrimary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildSection(
                  icon: Icons.info_outline_rounded,
                  iconColor: JobsyColors.workerPrimary,
                  title: 'Job Details',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Start Date', _formatDate(_job!['start_date'])),
                      if (_job!['duration_days'] != null)
                        _buildDetailRow('Duration', '${_job!['duration_days']} days'),
                      if (_job!['experience_level'] != null)
                        _buildDetailRow(
                          'Experience',
                          _job!['experience_level'].toString().toUpperCase(),
                        ),
                    ],
                  ),
                ),
                if (employer != null) ...[
                  const SizedBox(height: 12),
                  _buildSection(
                    icon: Icons.person_outline_rounded,
                    iconColor: JobsyColors.workerPrimary,
                    title: 'Posted By',
                    content: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                JobsyColors.workerPrimary.withOpacity(0.5),
                                JobsyColors.workerPrimary.withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: JobsyColors.surfaceElevated,
                            backgroundImage: employer['avatar_url'] != null &&
                                    employer['avatar_url'].toString().isNotEmpty
                                ? NetworkImage(employer['avatar_url'])
                                : null,
                            child: employer['avatar_url'] == null ||
                                    employer['avatar_url'].toString().isEmpty
                                ? const Icon(Icons.person_rounded,
                                    color: JobsyColors.workerPrimary, size: 26)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employer['full_name'] ?? 'Anonymous',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: JobsyColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (employer['location'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    employer['location'],
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: JobsyColors.textTertiary,
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
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: JobsyColors.background,
          border: Border(
            top: BorderSide(color: JobsyColors.border.withOpacity(0.4), width: 0.5),
          ),
        ),
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final jobStatus = _normalizedJobStatus();
              final hiredHere = _applicationStatus == 'accepted' ||
                  _applicationStatus == 'in_progress';
              final applicationsClosed =
                  jobStatus == 'in_progress' && !hiredHere;

              if (applicationsClosed) {
                return _buildInProgressClosedBanner();
              }
              if (_hasApplied) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((_applicationStatus == 'accepted' ||
                            _applicationStatus == 'in_progress') &&
                        !_acceptedBannerDismissed)
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF10B981), size: 22),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Application Accepted',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  Text(
                                    'You can start on this job!',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: JobsyColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              color: JobsyColors.textTertiary,
                              onPressed: _dismissAcceptedBanner,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            ),
                          ],
                        ),
                      ),
                    if (_applicationStatus != 'accepted' &&
                        _applicationStatus != 'in_progress' &&
                        _applicationStatus != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: _getStatusColor(_applicationStatus).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getStatusColor(_applicationStatus).withOpacity(0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getStatusIcon(_applicationStatus),
                              color: _getStatusColor(_applicationStatus),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Application ${_getStatusText(_applicationStatus)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _getStatusColor(_applicationStatus),
                                    ),
                                  ),
                                  Text(
                                    _getStatusSubtext(_applicationStatus),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: JobsyColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if ((_applicationStatus == 'accepted' ||
                            _applicationStatus == 'in_progress') &&
                        _applicationId != null &&
                        _job != null)
                      _buildGradientButton(
                        onPressed: () {
                          final myId = Supabase.instance.client.auth.currentUser?.id;
                          if (myId == null) return;
                          final emp = _job!['employer'] as Map<String, dynamic>?;
                          MessagingService.openChat(
                            context: context,
                            applicationId: _applicationId!,
                            jobId: widget.jobId,
                            jobTitle: _job!['title'] ?? 'Job',
                            employerId: _job!['employer_id'],
                            workerId: myId,
                            otherUserName: emp?['full_name'] ?? 'Employer',
                            isEmployer: false,
                          );
                        },
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message Employer',
                      ),
                  ],
                );
              }
              if (RoleService.isOwnJobPosting(_job?['employer_id']?.toString())) {
                return _buildGradientButton(
                  onPressed: null,
                  icon: Icons.block_rounded,
                  label: 'Your job posting',
                );
              }
              return _buildGradientButton(
                onPressed: _isApplying ? null : _applyToJob,
                icon: _isApplying ? null : Icons.send_rounded,
                label: _isApplying ? 'Applying...' : 'Apply Now',
                loading: _isApplying,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInProgressClosedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JobsyColors.border.withOpacity(0.9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.work_off_outlined,
            color: JobsyColors.workerPrimary.withOpacity(0.95),
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Job in progress — new applications are not accepted right now. '
              'The listing will open again if the hire withdraws or the job returns to active.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: JobsyColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
          color: iconColor.withOpacity(0.15),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.textPrimary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
  
  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    IconData? icon,
    required String label,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedPressButton(
        onPressed: onPressed,
        scaleDown: 0.97,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: JobsyColors.workerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: JobsyColors.workerPrimary.withOpacity(onPressed == null ? 0.1 : 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(color: JobsyColors.workerOnAccent, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: JobsyColors.workerOnAccent, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        label,
                        style: JobsyColors.workerGradientLabelStyle.copyWith(
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: JobsyColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: JobsyColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'accepted':
        return const Color(0xFF10B981);
      case 'in_progress':
        return JobsyColors.employerPrimary;
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return JobsyColors.textTertiary;
    }
  }
  
  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.autorenew_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }
  
  String _getStatusText(String? status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In progress';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Submitted';
    }
  }
  
  String _getStatusSubtext(String? status) {
    switch (status) {
      case 'pending':
        return 'Waiting for employer response';
      case 'accepted':
        return 'You can start working on this job!';
      case 'in_progress':
        return 'This job is underway. Keep in touch with the employer.';
      case 'rejected':
        return 'Better luck next time';
      default:
        return 'Application submitted';
    }
  }
}
