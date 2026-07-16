import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/colors.dart';
import '../../utils/error_messages.dart';
import '../../utils/external_job_presentation.dart';
import '../../utils/maps_launcher.dart';
import '../../widgets/external_job_image.dart';
import '../../widgets/vacancy_countdown_badge.dart';

class ExternalJobDetailScreen extends StatefulWidget {
  final String jobId;

  const ExternalJobDetailScreen({super.key, required this.jobId});

  @override
  State<ExternalJobDetailScreen> createState() => _ExternalJobDetailScreenState();
}

class _ExternalJobDetailScreenState extends State<ExternalJobDetailScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  bool _hasError = false;
  bool _vacancyClosed = false;
  DateTime _now = DateTime.now();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (_job == null) return;

    final remaining = ExternalJobPresentation.timeRemaining(_job!, now: _now);
    final interval = remaining != null && remaining.inDays < 2
        ? const Duration(seconds: 1)
        : const Duration(seconds: 30);

    _countdownTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_job != null && ExternalJobPresentation.isExpired(_job!, now: now)) {
        setState(() {
          _now = now;
          _vacancyClosed = true;
        });
        _countdownTimer?.cancel();
        return;
      }
      setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('external_jobs')
          .select('*')
          .eq('id', widget.jobId)
          .maybeSingle();
      if (!mounted) return;
      final closed = row != null && ExternalJobPresentation.isExpired(row);
      setState(() {
        _job = row;
        _loading = false;
        _hasError = row == null;
        _vacancyClosed = closed;
        _now = DateTime.now();
      });
      if (row != null && !closed) _startCountdownTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
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
        return 'External source';
    }
  }

  Future<void> _applyExternal() async {
    final url = _job?['external_url']?.toString();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the application page.')),
      );
    }
  }

  Future<void> _copyText(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _dialPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _emailContact(String email) async {
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JobsyColors.workerPrimary))
          : _hasError || _job == null
              ? _errorBody()
              : _vacancyClosed
                  ? _closedBody()
                  : _jobBody(context),
    );
  }

  Widget _closedBody() {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 56, color: JobsyColors.textTertiary.withValues(alpha: 0.7)),
                    const SizedBox(height: 16),
                    const Text(
                      'Vacancy closed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: JobsyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This opening has passed its closing date and was removed from Web Jobs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: JobsyColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody() {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                _hasError ? 'Job not found.' : friendlyErrorMessage('error'),
                style: const TextStyle(color: JobsyColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobBody(BuildContext context) {
    final job = _job!;
    final logoUrl = ExternalJobPresentation.logoImageUrl(job);
    final company = ExternalJobPresentation.cleanText(job['company_name']?.toString() ?? '');
    final posted = ExternalJobPresentation.postedLabel(job);
    final jobType = ExternalJobPresentation.jobTypeLabel(job);
    final description = ExternalJobPresentation.cleanText(job['description']?.toString() ?? '');
    final title = ExternalJobPresentation.cleanText(job['title']?.toString() ?? 'Job');
    final contacts = ExternalJobPresentation.resolveContacts(job);
    final sections = ExternalJobPresentation.parseDescriptionSections(description);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: logoUrl != null ? 180 : 140,
                pinned: true,
                backgroundColor: JobsyColors.background,
                foregroundColor: JobsyColors.textPrimary,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: _HeroHeader(
                    logoUrl: logoUrl,
                    company: company,
                    category: job['category']?.toString() ?? 'Other',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(_sourceLabel(job['source']?.toString()), JobsyColors.webJobsAccent),
                          _chip(job['category']?.toString() ?? 'Other', JobsyColors.workerPrimary),
                          if (jobType != null) _chip(jobType, JobsyColors.workerDark),
                          VacancyCountdownBadge(job: job, now: _now),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: JobsyColors.textPrimary,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (company != null && company.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _CompanyAvatar(company: company, imageUrl: logoUrl),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                company,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: JobsyColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      _factsCard(job, posted, _now),
                      if (sections.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Text(
                          'About this role',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: JobsyColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...sections.map(_descriptionSection),
                      ],
                      if (contacts.emails.isNotEmpty || contacts.phones.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Contact',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: JobsyColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final email in contacts.emails)
                          _contactTile(
                            icon: Icons.email_outlined,
                            label: email,
                            onTap: () => _emailContact(email),
                            onCopy: () => _copyText('Email', email),
                          ),
                        for (final phone in contacts.phones)
                          _contactTile(
                            icon: Icons.phone_outlined,
                            label: phone,
                            onTap: () => _dialPhone(phone),
                            onCopy: () => _copyText('Phone', phone),
                          ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: JobsyColors.webJobsAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: JobsyColors.webJobsAccent.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.public_rounded, color: JobsyColors.webJobsAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This listing is hosted on an external website. Tap Apply below to continue on the original job board.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: JobsyColors.textSecondary,
                                  height: 1.45,
                                ),
                              ),
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
        Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: JobsyColors.background,
            border: Border(top: BorderSide(color: JobsyColors.border.withValues(alpha: 0.5))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _applyExternal,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text(
                'Apply on website',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              style: JobsyColors.workerFilledButtonStyle(radius: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _factsCard(Map<String, dynamic> job, String? posted, DateTime now) {
    final salary = ExternalJobPresentation.cleanText(job['salary_text']?.toString() ?? '');
    final location = ExternalJobPresentation.cleanText(
      job['location']?.toString() ?? 'Location not specified',
    );
    final closing = ExternalJobPresentation.closingDateLabel(job);
    final countdown = ExternalJobPresentation.vacancyCountdownLabel(job, now: now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JobsyColors.border.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          _factRow(
            Icons.location_on_rounded,
            'Location',
            location,
            onTap: location != 'Location not specified'
                ? () => _openMaps(location)
                : null,
            trailing: location != 'Location not specified'
                ? const Icon(Icons.directions_rounded, size: 18, color: JobsyColors.workerPrimary)
                : null,
          ),
          const SizedBox(height: 12),
          _factRow(Icons.schedule_rounded, 'Vacancy', countdown),
          if (closing != null) ...[
            const SizedBox(height: 12),
            _factRow(Icons.event_rounded, 'Closes on', closing),
          ],
          if (salary.isNotEmpty) ...[
            const SizedBox(height: 12),
            _factRow(Icons.payments_rounded, 'Salary', salary, valueColor: Colors.green.shade700),
          ],
          if (posted != null) ...[
            const SizedBox(height: 12),
            _factRow(Icons.history_rounded, 'Listed', posted),
          ],
        ],
      ),
    );
  }

  Future<void> _openMaps(String location) async {
    final ok = await MapsLauncher.openPostedText(location);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }

  Widget _factRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: JobsyColors.workerPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: JobsyColors.workerPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.textTertiary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? JobsyColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }

  Widget _descriptionSection(ExternalJobDescriptionSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JobsyColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.heading != null) ...[
            Text(
              section.heading!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: JobsyColors.textPrimary,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 10),
          ],
          ...section.paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                p,
                style: const TextStyle(
                  fontSize: 14,
                  color: JobsyColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
          ),
          if (section.bullets.isNotEmpty)
            ...section.bullets.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: JobsyColors.workerPrimary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          color: JobsyColors.textSecondary,
                          height: 1.5,
                        ),
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

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: JobsyColors.roleChipDecoration(color),
      child: Text(
        label.toUpperCase(),
        style: JobsyColors.roleChipTextStyle(color),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required VoidCallback onCopy,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: JobsyColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: JobsyColors.workerPrimary),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: onCopy,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String? logoUrl;
  final String? company;
  final String category;

  const _HeroHeader({
    required this.logoUrl,
    required this.company,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _gradientFallback(category),
          Center(
            child: Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ExternalJobImage(
                imageUrl: logoUrl!,
                width: 68,
                height: 68,
                isLogo: true,
                placeholder: _CompanyAvatar(company: company, imageUrl: null, size: 68),
                errorWidget: _CompanyAvatar(company: company, imageUrl: null, size: 68),
              ),
            ),
          ),
        ],
      );
    }

    return _gradientFallback(category);
  }

  Widget _gradientFallback(String category) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: JobsyColors.workerCoverGradient,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CompanyAvatar(company: company, imageUrl: null, size: 64),
            const SizedBox(height: 10),
            Text(
              category,
              style: const TextStyle(
                color: JobsyColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyAvatar extends StatelessWidget {
  final String? company;
  final String? imageUrl;
  final double size;

  const _CompanyAvatar({
    required this.company,
    required this.imageUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final initial = ExternalJobPresentation.companyInitial(company);

    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: ExternalJobImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          isLogo: true,
          fit: BoxFit.contain,
          errorWidget: _initialBox(initial),
        ),
      );
    }

    return _initialBox(initial);
  }

  Widget _initialBox(String initial) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: JobsyColors.workerDark.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: JobsyColors.workerPrimary.withValues(alpha: 0.4)),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: JobsyColors.workerPrimary,
        ),
      ),
    );
  }
}
