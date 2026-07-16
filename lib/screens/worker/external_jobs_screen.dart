import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/page_transitions.dart';
import '../../utils/external_job_presentation.dart';
import '../../widgets/external_job_image.dart';
import '../../widgets/vacancy_countdown_badge.dart';
import 'external_job_detail_screen.dart';

/// Browse auto-imported job listings from external job boards.
class ExternalJobsScreen extends StatefulWidget {
  const ExternalJobsScreen({super.key});

  @override
  State<ExternalJobsScreen> createState() => _ExternalJobsScreenState();
}

class _ExternalJobsScreenState extends State<ExternalJobsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _selectedCategory;
  String? _lastSyncLabel;
  DateTime _now = DateTime.now();
  Timer? _countdownTimer;
  Timer? _searchDebounce;
  RealtimeChannel? _liveChannel;

  final List<String> _categories = ['All', ...AppConstants.jobCategories];

  @override
  void initState() {
    super.initState();
    _selectedCategory = 'All';
    _loadJobs();
    _subscribeLiveUpdates();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeLiveUpdates() {
    _liveChannel = Supabase.instance.client
        .channel('external-jobs-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'external_jobs',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row.isEmpty) return;
            _mergeLiveJob(row);
          },
        )
        .subscribe();
  }

  void _mergeLiveJob(Map<String, dynamic> row) {
    final id = row['id'];
    if (id == null) return;

    setState(() {
      final active = row['is_active'] == true;
      _jobs.removeWhere((j) => j['id'] == id);
      if (active) {
        _jobs.insert(0, row);
        _jobs.sort((a, b) {
          final ai = DateTime.tryParse(a['imported_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bi = DateTime.tryParse(b['imported_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bi.compareTo(ai);
        });
        final imported = row['imported_at']?.toString();
        if (imported != null) {
          final dt = DateTime.tryParse(imported);
          if (dt != null) _lastSyncLabel = _formatSyncTime(dt.toLocal());
        }
      }
      _applyFilters();
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), _applyFilters);
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final response = await Supabase.instance.client
          .from('external_jobs')
          .select('*')
          .eq('is_active', true)
          .order('imported_at', ascending: false)
          .limit(300);

      final jobs = List<Map<String, dynamic>>.from(response);

      String? syncLabel;
      if (jobs.isNotEmpty) {
        final latest = jobs.first['imported_at']?.toString();
        if (latest != null) {
          final dt = DateTime.tryParse(latest);
          if (dt != null) {
            syncLabel = _formatSyncTime(dt.toLocal());
          }
        }
      }

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _lastSyncLabel = syncLabel;
          _now = DateTime.now();
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('External jobs load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  String _formatSyncTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 48) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _applyFilters() {
    var list = List<Map<String, dynamic>>.from(_jobs);
    list = list.where((j) => !ExternalJobPresentation.isExpired(j, now: _now)).toList();
    final q = _searchController.text.trim().toLowerCase();

    if (_selectedCategory != null && _selectedCategory != 'All') {
      list = list.where((j) => j['category'] == _selectedCategory).toList();
    }

    if (q.isNotEmpty) {
      list = list.where((j) {
        final hay = [
          j['title'],
          j['description'],
          j['location'],
          j['company_name'],
          j['category'],
        ].whereType<String>().join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }

    if (!mounted) return;
    setState(() => _filtered = list);
  }

  String _sourceLabel(String? source) {
    switch (source) {
      case 'google_jobs':
        return 'Google Jobs';
      case 'facebook':
        return 'Facebook';
      case 'indeed_bw':
      case 'indeed_gaborone':
      case 'indeed_francistown':
      case 'indeed_construction':
      case 'indeed_driver':
      case 'indeed_hospitality':
        return 'Indeed';
      case 'skyjobs':
      case 'skyjobs_feed':
        return 'Sky Jobs';
      case 'jobcentral':
        return 'Jobcentral';
      case 'joblist_bw':
        return 'Joblist';
      case 'alljobspo':
        return 'AllJobs';
      case 'hirebw':
        return 'Hire BW';
      default:
        return 'Web';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: Text(
                      AppConstants.webJobsFeedTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: JobsyColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadJobs,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          JobsyColors.webJobsAccent.withOpacity(0.15),
                          JobsyColors.workerPrimary.withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: JobsyColors.webJobsAccent.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.public_rounded,
                            color: JobsyColors.workerPrimary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Auto-imported from job boards',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: JobsyColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _lastSyncLabel != null
                                    ? 'Last updated $_lastSyncLabel · ${_jobs.length} live listings · Indeed, Facebook & more'
                                    : 'Indeed, Sky Jobs, Facebook & more — listings update live as they are imported',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: JobsyColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: JobsyColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search title, company, location…',
                      hintStyle: const TextStyle(color: JobsyColors.textTertiary, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: JobsyColors.textSecondary, size: 22),
                      filled: true,
                      fillColor: JobsyColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final selected = _selectedCategory == category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => _selectedCategory = category);
                              _applyFilters();
                            },
                            selectedColor: JobsyColors.workerPrimary.withOpacity(0.18),
                            checkmarkColor: JobsyColors.workerOnAccent,
                            labelStyle: TextStyle(
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? JobsyColors.workerOnAccent
                                  : JobsyColors.textSecondary,
                              fontSize: 12.5,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? JobsyColors.workerPrimary.withOpacity(0.5)
                                  : JobsyColors.border.withOpacity(0.5),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_filtered.length} listing${_filtered.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: JobsyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: JobsyColors.workerPrimary),
                    )
                  : _hasError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Could not load external jobs.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: JobsyColors.textSecondary),
                                ),
                                const SizedBox(height: 12),
                                TextButton(onPressed: _loadJobs, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.work_off_outlined,
                                        size: 48,
                                        color: JobsyColors.textTertiary.withOpacity(0.6)),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No listings yet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: JobsyColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _lastSyncLabel == null
                                          ? 'Listings sync every 8 hours from online job boards. '
                                              'If this stays empty, trigger import-external-jobs once from the Supabase dashboard or wait for the next cron run.'
                                          : 'No jobs match your filters. Try another category or clear search.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: JobsyColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadJobs,
                              color: JobsyColors.workerPrimary,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _filtered.length,
                                itemBuilder: (context, index) {
                                  final job = _filtered[index];
                                  return AnimatedListItem(
                                    index: index,
                                    child: _ExternalJobCard(
                                      job: job,
                                      now: _now,
                                      sourceLabel: _sourceLabel(job['source']?.toString()),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          JobsyPageRoute(
                                            page: ExternalJobDetailScreen(
                                              jobId: job['id'].toString(),
                                            ),
                                            transition: JobsyTransition.fadeSlide,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExternalJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final DateTime now;
  final String sourceLabel;
  final VoidCallback onTap;

  const _ExternalJobCard({
    required this.job,
    required this.now,
    required this.sourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = ExternalJobPresentation.cleanText(job['title']?.toString() ?? 'Job');
    final company = ExternalJobPresentation.cleanText(job['company_name']?.toString() ?? '');
    final location = ExternalJobPresentation.cleanText(job['location']?.toString() ?? 'Location not specified');
    final category = job['category']?.toString() ?? 'Other';
    final salary = job['salary_text']?.toString();
    final description = ExternalJobPresentation.cleanText(job['description']?.toString() ?? '');
    final summary = description.isNotEmpty ? ExternalJobPresentation.shortSummary(description) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: JobsyColors.border.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExternalJobLogoTile(job: job, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _miniChip(sourceLabel, JobsyColors.webJobsAccent),
                            const SizedBox(width: 6),
                            _miniChip(category, JobsyColors.workerPrimary),
                            const Spacer(),
                            VacancyCountdownBadge(job: job, now: now, compact: true),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: JobsyColors.textPrimary,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (company.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            company,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: JobsyColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (summary != null && summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: JobsyColors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: JobsyColors.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: JobsyColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (salary != null && salary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  salary,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: JobsyColors.roleChipDecoration(color),
      child: Text(
        label.toUpperCase(),
        style: JobsyColors.roleChipTextStyle(color),
      ),
    );
  }
}
