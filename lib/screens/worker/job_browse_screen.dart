import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/page_transitions.dart';
import '../../widgets/modern_widgets.dart';
import '../../services/job_matching_service.dart';
import '../../widgets/jobsy_app_shell.dart';
import 'job_details_screen.dart';
import 'external_jobs_screen.dart';

class JobBrowseScreen extends StatefulWidget {
  const JobBrowseScreen({super.key});
  
  @override
  State<JobBrowseScreen> createState() => _JobBrowseScreenState();
}

class _JobBrowseScreenState extends State<JobBrowseScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _filteredJobs = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;
  String? _selectedCategory;
  List<String> _workerSkills = [];
  String? _workerLocation;
  String? _workerBio;
  Timer? _realtimeDebounce;
  RealtimeChannel? _liveJobsChannel;

  static const int _pageSize = 50;
  int _loadedCount = 0;

  final List<String> _categories = [
    'All',
    ...AppConstants.jobCategories,
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = 'All';
    _scrollController.addListener(_onScroll);
    _loadWorkerProfile();
    _loadJobs();
    _subscribeLiveJobs();
  }

  void _subscribeLiveJobs() {
    _liveJobsChannel = Supabase.instance.client
        .channel('worker-browse-jobs-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'jobs',
          callback: (_) {
            _realtimeDebounce?.cancel();
            _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
              if (mounted) _loadJobs();
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadWorkerProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('skills, location, bio')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _workerSkills = row['skills'] != null
            ? List<String>.from(row['skills'])
            : [];
        _workerLocation = row['location']?.toString();
        _workerBio = row['bio']?.toString();
      });
      _applyFilters();
    } catch (e) {
      debugPrint('Load worker profile for matching: $e');
    }
  }

  static const _employerSelect = '''
            *,
            employer:profiles!employer_id (
              full_name,
              avatar_url,
              location
            )
          ''';

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    if (_liveJobsChannel != null) {
      Supabase.instance.client.removeChannel(_liveJobsChannel!);
    }
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreJobs();
    }
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _loadedCount = 0;
      _hasMore = true;
      _jobs = [];
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final response = await Supabase.instance.client
          .from('jobs')
          .select(_employerSelect)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      List<Map<String, dynamic>> availableJobs =
          List<Map<String, dynamic>>.from(response);
      _loadedCount = availableJobs.length;
      _hasMore = availableJobs.length == _pageSize;

      if (userId != null) {
        availableJobs = await _filterAccepted(availableJobs, userId);
      }

      if (mounted) {
        setState(() {
          _jobs = availableJobs;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading jobs: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _loadMoreJobs() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final from = _loadedCount;
      final to = from + _pageSize - 1;

      final response = await Supabase.instance.client
          .from('jobs')
          .select(_employerSelect)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .range(from, to);

      List<Map<String, dynamic>> newJobs =
          List<Map<String, dynamic>>.from(response);
      _loadedCount += newJobs.length;
      _hasMore = newJobs.length == _pageSize;

      if (userId != null) {
        newJobs = await _filterAccepted(newJobs, userId);
      }

      if (mounted) {
        setState(() {
          _jobs = [..._jobs, ...newJobs];
          _applyFilters();
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Load more jobs: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<List<Map<String, dynamic>>> _filterAccepted(
    List<Map<String, dynamic>> jobs,
    String userId,
  ) async {
    try {
      // Hide own postings and jobs already accepted as worker.
      var filtered = jobs
          .where((j) => j['employer_id']?.toString() != userId)
          .toList();

      final myAccepted = await Supabase.instance.client
          .from('job_applications')
          .select('job_id')
          .eq('worker_id', userId)
          .eq('status', 'accepted');
      final acceptedJobIds =
          (myAccepted as List).map((a) => a['job_id']).toSet();
      return filtered.where((j) => !acceptedJobIds.contains(j['id'])).toList();
    } catch (e) {
      debugPrint('Filter accepted: $e');
      return jobs.where((j) => j['employer_id']?.toString() != userId).toList();
    }
  }
  
  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_jobs);
    
    if (_selectedCategory != null && _selectedCategory != 'All') {
      filtered = filtered.where((job) => job['category'] == _selectedCategory).toList();
    }
    
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((job) {
        final title = (job['title'] as String? ?? '').toLowerCase();
        final description = (job['description'] as String? ?? '').toLowerCase();
        final location = (job['location'] as String? ?? '').toLowerCase();
        final skills = (job['required_skills'] as List? ?? [])
            .map((s) => s.toString().toLowerCase())
            .join(' ');
        final employerLoc =
            (job['employer']?['location'] as String? ?? '').toLowerCase();
        return title.contains(query) ||
            description.contains(query) ||
            location.contains(query) ||
            skills.contains(query) ||
            employerLoc.contains(query);
      }).toList();
    }

    filtered.sort((a, b) {
      final scoreA = JobMatchingService.scoreJobForWorker(
        job: a,
        workerSkills: _workerSkills,
        workerLocation: _workerLocation,
        workerBio: _workerBio,
      ).score;
      final scoreB = JobMatchingService.scoreJobForWorker(
        job: b,
        workerSkills: _workerSkills,
        workerLocation: _workerLocation,
        workerBio: _workerBio,
      ).score;
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return (b['created_at'] as String).compareTo(a['created_at'] as String);
    });
    
    setState(() => _filteredJobs = filtered);
  }

  int _topMatchCount() {
    return _filteredJobs.where((job) {
      return JobMatchingService.scoreJobForWorker(
        job: job,
        workerSkills: _workerSkills,
        workerLocation: _workerLocation,
        workerBio: _workerBio,
      ).score >= 45;
    }).length;
  }
  
  String _getBudgetText(Map<String, dynamic> job) {
    final amount = job['budget_amount'];
    final type = job['budget_type'];
    
    switch (type) {
      case 'fixed':
        return 'P$amount Fixed';
      case 'hourly':
        return 'P$amount/hr';
      case 'daily':
        return 'P$amount/day';
      case 'weekly':
        return 'P$amount/week';
      default:
        return 'P$amount';
    }
  }
  
  String _getTimeAgo(String timestamp) {
    final date = DateTime.parse(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        color: JobsyColors.workerPrimary,
        backgroundColor: JobsyColors.surfaceLight,
        child: Column(
          children: [
            JobsyScreenHeader(
              title: 'Find Work',
              subtitle: 'Curated local opportunities & verified listings',
              accentColor: JobsyColors.workerPrimary,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JobsyColors.workerPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: JobsyColors.workerPrimary.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  '${_filteredJobs.length} open',
                  style: const TextStyle(
                    color: JobsyColors.workerPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: JobsyColors.border.withOpacity(0.6),
                        width: 0.7,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _applyFilters(),
                      style: const TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Search jobs, locations, skills...',
                        hintStyle: const TextStyle(color: JobsyColors.textTertiary, fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded, color: JobsyColors.textSecondary, size: 22),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                color: JobsyColors.textTertiary,
                                onPressed: () {
                                  _searchController.clear();
                                  _applyFilters();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: JobsyColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_topMatchCount() > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: JobsyColors.workerPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: JobsyColors.workerPrimary.withOpacity(0.28),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: JobsyColors.workerPrimary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_topMatchCount()} job${_topMatchCount() == 1 ? '' : 's'} match your skills & location',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: JobsyColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          JobsyPageRoute(
                            page: const ExternalJobsScreen(),
                            transition: JobsyTransition.fadeSlide,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              JobsyColors.webJobsAccent.withValues(alpha: 0.18),
                              JobsyColors.workerPrimary.withValues(alpha: 0.12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: JobsyColors.webJobsAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: JobsyColors.webJobsAccent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.public_rounded,
                                  color: JobsyColors.webJobsAccent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppConstants.webJobsFeedTitle,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: JobsyColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      AppConstants.webJobsFeedSubtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: JobsyColors.textSecondary,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: JobsyColors.workerPrimary.withOpacity(0.8)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = _selectedCategory == category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: AnimatedPressButton(
                            onPressed: () {
                              setState(() => _selectedCategory = category);
                              _applyFilters();
                            },
                            scaleDown: 0.94,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? const LinearGradient(
                                        colors: JobsyColors.workerGradient,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isSelected ? null : JobsyColors.surfaceLight,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: isSelected ? Colors.transparent : JobsyColors.border.withOpacity(0.5),
                                  width: 0.7,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: JobsyColors.workerPrimary.withOpacity(0.35),
                                          blurRadius: 14,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    color: isSelected ? JobsyColors.workerOnAccent : JobsyColors.textSecondary,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 13,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _hasError
                      ? _buildErrorState()
                      : _filteredJobs.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                              itemCount: _filteredJobs.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _filteredJobs.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                final job = _filteredJobs[index];
                                return AnimatedListItem(
                                  index: index,
                                  child: _buildJobCard(job),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: ShimmerLoading(height: 170, borderRadius: 18),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: JobsyColors.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Could not load jobs',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadJobs,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: JobsyColors.workerFilledButtonStyle(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                radius: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildJobCard(Map<String, dynamic> job) {
    final employer = job['employer'] as Map<String, dynamic>?;
    final employerName = employer?['full_name'] ?? 'Anonymous';
    final employerPhoto = employer?['avatar_url'];
    final employerLocation = employer?['location']?.toString();
    final match = JobMatchingService.scoreJobForWorker(
      job: job,
      workerSkills: _workerSkills,
      workerLocation: _workerLocation,
      workerBio: _workerBio,
    );
    
    return JobsyGlowCard(
      glowColor: JobsyColors.workerPrimary,
      glowIntensity: 0.06,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      onTap: () {
        Navigator.push(
          context,
          JobsyPageRoute(
            page: JobDetailsScreen(jobId: job['id']),
            transition: JobsyTransition.fadeSlide,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  radius: 19,
                  backgroundColor: JobsyColors.surfaceElevated,
                  backgroundImage: employerPhoto != null ? NetworkImage(employerPhoto) : null,
                  child: employerPhoto == null
                      ? const Icon(Icons.person_rounded, color: JobsyColors.workerPrimary, size: 20)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: JobsyColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _getTimeAgo(job['created_at']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: JobsyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JobsyColors.workerPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: JobsyColors.workerPrimary.withOpacity(0.3),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  job['category'] ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.workerPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          if (match.label.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: JobsyColors.workerPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JobsyColors.workerPrimary.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${match.label} · ${match.score}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.workerPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            job['title'] ?? '',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: JobsyColors.textPrimary,
              letterSpacing: -0.2,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            job['description'] ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              color: JobsyColors.textSecondary,
              height: 1.45,
            ),
          ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: JobsyColors.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Job site: ${job['location'] ?? 'Not specified'}',
                        style: const TextStyle(fontSize: 13, color: JobsyColors.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
          if (employerLocation != null && employerLocation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.business_outlined, size: 15, color: JobsyColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Employer based in $employerLocation',
                    style: const TextStyle(fontSize: 12.5, color: JobsyColors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
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
                  _getBudgetText(job),
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
          if (job['required_skills'] != null && (job['required_skills'] as List).isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (job['required_skills'] as List).take(3).map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: JobsyColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: JobsyColors.border.withOpacity(0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    skill.toString(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: JobsyColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
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
              'No jobs found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: JobsyColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty || _selectedCategory != 'All'
                  ? 'Try adjusting your filters'
                  : 'Check back soon for new opportunities',
              style: const TextStyle(
                fontSize: 14,
                color: JobsyColors.textTertiary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
