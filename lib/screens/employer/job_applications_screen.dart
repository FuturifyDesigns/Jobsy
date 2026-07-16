import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/colors.dart';
import '../../config/page_transitions.dart';
import '../../widgets/modern_widgets.dart';
import '../../services/messaging_service.dart';
import '../../services/application_ranking_service.dart';
import '../../widgets/application_qualification_viewer.dart';
import '../../utils/error_messages.dart';

class JobApplicationsScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  
  const JobApplicationsScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });
  
  @override
  State<JobApplicationsScreen> createState() => _JobApplicationsScreenState();
}

class _JobApplicationsScreenState extends State<JobApplicationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _sortByScore = true;
  String? _jobDescription;
  List<String> _requiredSkills = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadJobDetails();
  }

  Future<void> _loadJobDetails() async {
    try {
      final row = await Supabase.instance.client
          .from('jobs')
          .select('description, location, required_skills')
          .eq('id', widget.jobId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final desc = row['description']?.toString() ?? '';
      final loc = row['location']?.toString() ?? '';
      setState(() {
        _jobDescription = '$desc $loc'.trim();
        _requiredSkills = row['required_skills'] != null
            ? List<String>.from(row['required_skills'])
            : [];
      });
    } catch (_) {}
  }
  
  @override
  void dispose() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    _tabController.dispose();
    super.dispose();
    if (messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.clearSnackBars();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 170,
            floating: false,
            pinned: true,
            backgroundColor: JobsyColors.background,
            foregroundColor: JobsyColors.textPrimary,
            elevation: 0,
            title: const Text('Applications',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF3F3F46),
                          Color(0xFF27272A),
                          Color(0xFF1A1A2E),
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 60),
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
                          child: const Icon(Icons.people_alt_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                  'Job Applications',
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
                                widget.jobTitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.75),
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: JobsyColors.background,
                child: TabBar(
                  controller: _tabController,
                  labelColor: JobsyColors.employerPrimary,
                  unselectedLabelColor: JobsyColors.textTertiary,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  indicatorColor: JobsyColors.employerPrimary,
                  indicatorWeight: 2.5,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: JobsyColors.border.withOpacity(0.3),
                  dividerHeight: 0.5,
                  tabs: const [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active'),
                    Tab(text: 'Closed'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            Column(
              children: [
                if (_sortByScore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 18, color: JobsyColors.employerPrimary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Sorted by Jobsy helper score (best first)',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: JobsyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _sortByScore = false),
                          child: const Text('By date'),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _sortByScore = true),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Sort by helper score'),
                      ),
                    ),
                  ),
                Expanded(child: _buildApplicationsList('pending')),
              ],
            ),
            _buildApplicationsList('active'),
            _buildApplicationsList('closed'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildApplicationsList(String listKind) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('job_applications')
          .stream(primaryKey: ['id'])
          .eq('job_id', widget.jobId)
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
          return const Center(child: CircularProgressIndicator());
        }
        
        final applications = snapshot.data!.where((app) {
          final status = app['status'] as String?;
          if (listKind == 'active') {
            return status == 'accepted' || status == 'in_progress';
          }
          if (listKind == 'closed') {
            return status == 'rejected' ||
                status == 'withdrawn' ||
                status == 'cancelled';
          }
          return status == listKind;
        }).toList();

        if (listKind == 'pending' && _sortByScore && applications.isNotEmpty) {
          applications.sort((a, b) {
            final scoreA = ApplicationRankingService.rank(
              application: a,
              worker: null,
              jobDescription: _jobDescription,
              jobTitle: widget.jobTitle,
              requiredSkills: _requiredSkills,
            ).score;
            final scoreB = ApplicationRankingService.rank(
              application: b,
              worker: null,
              jobDescription: _jobDescription,
              jobTitle: widget.jobTitle,
              requiredSkills: _requiredSkills,
            ).score;
            return scoreB.compareTo(scoreA);
          });
        }
        
        if (applications.isEmpty) {
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
                        color: JobsyColors.employerPrimary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.inbox_rounded,
                      size: 40,
                      color: JobsyColors.employerPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    listKind == 'closed'
                        ? 'No closed applications'
                        : 'No $listKind applications',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: JobsyColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listKind == 'pending'
                        ? 'New applicants will appear here'
                        : listKind == 'active'
                            ? 'Accept an applicant to collaborate here'
                            : listKind == 'closed'
                                ? 'Rejected, withdrawn, and cancelled applications appear here'
                                : 'Nothing here yet',
                    style: const TextStyle(
                      fontSize: 13,
                      color: JobsyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: applications.length,
          itemBuilder: (context, index) {
            return AnimatedListItem(
              index: index,
              child: _buildApplicationCard(
                applications[index],
                showHelperRank: listKind == 'pending',
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildApplicationCard(
    Map<String, dynamic> application, {
    bool showHelperRank = false,
  }) {
    final workerId = application['worker_id'] as String;
    final appStatus = application['status'] as String;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', workerId),
      builder: (context, snapshot) {
        final worker = snapshot.data != null && snapshot.data!.isNotEmpty
            ? snapshot.data!.first
            : null;

        final rank = ApplicationRankingService.rank(
          application: application,
          worker: worker,
          jobDescription: _jobDescription,
          jobTitle: widget.jobTitle,
          requiredSkills: _requiredSkills,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                JobsyColors.surfaceLight,
                JobsyColors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _getStatusColor(appStatus).withOpacity(0.2),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: _getStatusColor(appStatus).withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Worker info
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: JobsyColors.employerPrimary.withOpacity(0.2),
                          backgroundImage: worker != null &&
                                  worker['avatar_url'] != null &&
                                  worker['avatar_url'].toString().isNotEmpty
                              ? NetworkImage(worker['avatar_url'].toString())
                              : null,
                          child: worker == null ||
                                  worker['avatar_url'] == null ||
                                  worker['avatar_url'].toString().isEmpty
                              ? Text(
                                  () {
                                    final name =
                                        worker?['full_name'] as String?;
                                    if (name != null && name.isNotEmpty) {
                                      return name[0].toUpperCase();
                                    }
                                    return 'W';
                                  }(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
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
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      worker?['full_name'] ?? 'Loading...',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: JobsyColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(appStatus).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _getStatusColor(appStatus).withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getStatusIcon(appStatus),
                                          size: 12,
                                          color: _getStatusColor(appStatus),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          appStatus.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _getStatusColor(appStatus),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (worker?['location'] != null)
                                Text(
                                  worker!['location'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: JobsyColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (worker != null &&
                            worker['rating'] != null &&
                            (worker['rating'] as num) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  (worker['rating'] as num).toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: JobsyColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    if (showHelperRank) ...[
                      const SizedBox(height: 12),
                      _buildHelperRankChip(rank),
                    ],
                    
                    // Cover letter
                    if (application['cover_letter'] != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Cover letter:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: JobsyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        application['cover_letter'],
                        style: TextStyle(
                          fontSize: 14,
                          color: JobsyColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],

                    if (application['references_text'] != null &&
                        (application['references_text'].toString().trim().isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 18, color: JobsyColors.employerPrimary.withOpacity(0.9)),
                          const SizedBox(width: 8),
                          const Text(
                            'References:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: JobsyColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        application['references_text'].toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: JobsyColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],

                    if (application['additional_info'] != null &&
                        (application['additional_info'].toString().trim().isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.note_alt_outlined,
                              size: 18, color: JobsyColors.employerPrimary.withOpacity(0.9)),
                          const SizedBox(width: 8),
                          const Text(
                            'Additional details:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: JobsyColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        application['additional_info'].toString(),
                        style: TextStyle(
                          fontSize: 14,
                          color: JobsyColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],

                    ..._qualificationAttachmentWidgets(application),
                    
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => ApplicationDetailSheet.show(
                          context,
                          application: application,
                          worker: worker,
                          rank: showHelperRank ? rank : null,
                        ),
                        icon: const Icon(Icons.open_in_full_rounded, size: 18),
                        label: const Text('View full application & files'),
                      ),
                    ),
                    
                    // Applied date
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: JobsyColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Applied: ${_formatDate(application['created_at'])}',
                          style: TextStyle(fontSize: 12, color: JobsyColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action buttons (only for pending)
              if (appStatus == 'pending') ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handleApplication(application, 'rejected'),
                          icon: const Icon(Icons.close),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleApplication(application, 'accepted'),
                          icon: const Icon(Icons.check),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Message when actively working together
              if (appStatus == 'accepted' || appStatus == 'in_progress') ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final myId = Supabase.instance.client.auth.currentUser?.id;
                        if (myId == null) return;
                        MessagingService.openChat(
                          context: context,
                          applicationId: application['id'],
                          jobId: widget.jobId,
                          jobTitle: widget.jobTitle,
                          employerId: myId,
                          workerId: application['worker_id'],
                          otherUserName: worker?['full_name'] ?? 'Worker',
                          isEmployer: true,
                          otherUserAvatar: worker?['avatar_url']?.toString(),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Message Worker'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JobsyColors.employerPrimary,
                        foregroundColor: JobsyColors.employerOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildHelperRankChip(ApplicationRankResult rank) {
    Color color;
    if (rank.isStrong) {
      color = const Color(0xFF10B981);
    } else if (rank.isGood) {
      color = JobsyColors.employerPrimary;
    } else if (rank.isFair) {
      color = const Color(0xFFF59E0B);
    } else {
      color = const Color(0xFFEF4444);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jobsy helper · ${rank.tier} (${rank.score}/100)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (rank.pros.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rank.pros.first,
                    style: const TextStyle(
                      fontSize: 12,
                      color: JobsyColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQualificationFile(String storagePath, String fileName) async {
    await ApplicationQualificationViewer.open(
      context,
      storagePath: storagePath,
      fileName: fileName,
    );
  }

  List<Widget> _qualificationAttachmentWidgets(Map<String, dynamic> application) {
    final items = ApplicationQualificationViewer.parseFiles(
      application['qualification_files'],
    );
    if (items.isEmpty) return const [];

    return [
      const SizedBox(height: 16),
      Row(
        children: [
          Icon(Icons.badge_outlined,
              size: 18, color: JobsyColors.employerPrimary.withOpacity(0.9)),
          const SizedBox(width: 8),
          const Text(
            'Qualifications:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: JobsyColors.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((f) {
          return ActionChip(
            avatar: Icon(
              f['name']!.toLowerCase().endsWith('.pdf')
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
              size: 18,
              color: JobsyColors.employerPrimary,
            ),
            label: Text(
              f['name']!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            onPressed: () => _openQualificationFile(f['path']!, f['name']!),
          );
        }).toList(),
      ),
    ];
  }

  Future<void> _handleApplication(
    Map<String, dynamic> application,
    String newStatus,
  ) async {
    final applicationId = application['id'] as String;
    final workerId = application['worker_id'] as String;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JobsyColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              newStatus == 'accepted' ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: newStatus == 'accepted' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                newStatus == 'accepted' ? 'Accept Application?' : 'Reject Application?',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          newStatus == 'accepted'
              ? 'This worker will be notified and can start working on the job.'
              : 'This worker will be notified that their application was declined.',
          style: const TextStyle(color: JobsyColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: JobsyColors.textSecondary),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'accepted' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(newStatus == 'accepted' ? 'Accept' : 'Reject',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      // Update application status
      final now = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('job_applications')
          .update({
            'status': newStatus,
            'updated_at': now,
          })
          .eq('id', applicationId);

      if (newStatus == 'accepted') {
        await Supabase.instance.client.from('jobs').update({
          'status': 'in_progress',
          'updated_at': now,
        }).eq('id', widget.jobId);
      }

      if (newStatus == 'accepted' && mounted) {
        final myId = Supabase.instance.client.auth.currentUser?.id;
        if (myId != null) {
          await MessagingService.ensureConversationExists(
            applicationId: applicationId,
            jobId: widget.jobId,
            employerId: myId,
            workerId: workerId,
          );
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newStatus == 'accepted' ? Icons.check_circle : Icons.cancel,
                  color: JobsyColors.surfaceLight,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    newStatus == 'accepted'
                        ? 'Application accepted — you can message from Active or My Jobs.'
                        : 'Application rejected.',
                  ),
                ),
              ],
            ),
            backgroundColor:
                newStatus == 'accepted' ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
            dismissDirection: DismissDirection.horizontal,
            action: newStatus == 'accepted'
                ? SnackBarAction(
                    label: 'Message',
                    textColor: Colors.white,
                    onPressed: () {
                      messenger.hideCurrentSnackBar();
                      final myId = Supabase.instance.client.auth.currentUser?.id;
                      if (myId == null) return;
                      MessagingService.openChat(
                        context: context,
                        applicationId: applicationId,
                        jobId: widget.jobId,
                        jobTitle: widget.jobTitle,
                        employerId: myId,
                        workerId: workerId,
                        otherUserName: 'Worker',
                        isEmployer: true,
                      );
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(friendlyErrorMessage(e))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'accepted':
        return const Color(0xFF10B981);
      case 'in_progress':
        return JobsyColors.employerPrimary;
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'withdrawn':
        return const Color(0xFF94A3B8);
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return JobsyColors.textTertiary;
    }
  }
  
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.autorenew_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'withdrawn':
        return Icons.exit_to_app_rounded;
      case 'cancelled':
        return Icons.block_rounded;
      default:
        return Icons.help_rounded;
    }
  }
  
  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
