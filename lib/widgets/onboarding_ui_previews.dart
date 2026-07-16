import 'package:flutter/material.dart';

import '../config/colors.dart';
import 'jobsy_app_shell.dart';
import 'modern_widgets.dart';

/// Miniature replicas of real Jobsy screens for onboarding.
class OnboardingUiPreviews {
  OnboardingUiPreviews._();

  static Widget frame({
    required Widget child,
    String? label,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
      decoration: BoxDecoration(
        color: JobsyColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JobsyColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: JobsyColors.navBarBackground,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: JobsyColors.textTertiary,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }

  // ── Worker ───────────────────────────────────────────────────────────

  static Widget workerPortal(Color accent) {
    return frame(
      label: 'WORKER PORTAL',
      child: Column(
        children: [
          JobsyAppBar(
            accentColor: accent,
            isEmployer: false,
            userName: 'Thabo',
            onLeadingPressed: () {},
            onProfileTap: () {},
          ),
          JobsyScreenHeader(
            title: 'Find Work',
            subtitle: 'Curated local opportunities',
            accentColor: accent,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Text(
                '24 open',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _searchField(accent, 'Search jobs, locations, skills…'),
          ),
          const Spacer(),
          _bottomNavPreview(accent, ['Find', 'Jobs', 'Wallet', 'Chat', 'Me'], 0),
        ],
      ),
    );
  }

  static Widget workerLocalJobCard(Color accent) {
    return frame(
      label: 'FIND JOBS TAB',
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: JobsyGlowCard(
          glowColor: accent,
          glowIntensity: 0.06,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: JobsyColors.surfaceElevated,
                    child: Icon(Icons.person_rounded, size: 18, color: accent),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BuildRight BW',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: JobsyColors.textPrimary)),
                        Text('2d ago',
                            style: TextStyle(
                                fontSize: 9, color: JobsyColors.textTertiary)),
                      ],
                    ),
                  ),
                  _chip('Construction', accent),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Text('Skills match · 87%',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: accent)),
              ),
              const SizedBox(height: 10),
              const Text('Electrician — Gaborone CBD',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: JobsyColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Commercial wiring for new office block…',
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 10,
                      color: JobsyColors.textSecondary,
                      height: 1.35)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 12, color: JobsyColors.textTertiary),
                  const SizedBox(width: 4),
                  const Text('Gaborone',
                      style: TextStyle(
                          fontSize: 10, color: JobsyColors.textTertiary)),
                  const Spacer(),
                  Text('P450/day',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget workerWebJobs(Color accent) {
    return frame(
      label: 'WEB JOBS',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: JobsyColors.surface,
              border: Border(
                bottom: BorderSide(color: JobsyColors.border.withValues(alpha: 0.5)),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.arrow_back_rounded, size: 18, color: JobsyColors.textSecondary),
                SizedBox(width: 8),
                Text('Web Jobs',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: JobsyColors.textPrimary)),
                Spacer(),
                Icon(Icons.refresh_rounded, size: 18, color: JobsyColors.textTertiary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JobsyColors.border.withValues(alpha: 0.45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.85),
                          JobsyColors.webJobsAccent.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _chip('GOOGLE JOBS', JobsyColors.webJobsAccent),
                        ),
                        Center(
                          child: Icon(Icons.apartment_rounded,
                              color: Colors.white.withValues(alpha: 0.5), size: 28),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _chip('CONSTRUCTION', accent),
                            const Spacer(),
                            _chip('7 days left', JobsyColors.warning),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('PLUMBER – emmis construction',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: JobsyColors.textPrimary)),
                        const SizedBox(height: 4),
                        const Text('emmis construction',
                            style: TextStyle(
                                fontSize: 10,
                                color: JobsyColors.textSecondary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 11, color: JobsyColors.textTertiary),
                            const SizedBox(width: 3),
                            const Text('Gaborone',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: JobsyColors.textTertiary)),
                          ],
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
    );
  }

  static Widget workerJobDetail(Color accent) {
    return frame(
      label: 'JOB DETAIL',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('CONSTRUCTION', accent),
                _chip('7 days left', JobsyColors.warning),
              ],
            ),
            const SizedBox(height: 10),
            const Text('PLUMBER – emmis construction',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JobsyColors.border.withValues(alpha: 0.45)),
              ),
              child: Column(
                children: [
                  _factRow(Icons.location_on_rounded, 'Location', 'Gaborone', accent),
                  const SizedBox(height: 8),
                  _factRow(Icons.schedule_rounded, 'Vacancy', '7 days left', accent),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: JobsyGradientButton(
                text: 'Apply on website',
                gradient: [accent, JobsyColors.workerDark],
                height: 44,
                fontSize: 13,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget workerMyJobs(Color accent) {
    return frame(
      label: 'MY JOBS TAB',
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: JobsyColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: _tabPill('Active', true, accent)),
                Expanded(child: _tabPill('Past', false, accent)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _applicationTile('Site Electrician', 'In progress', accent, JobsyColors.success),
                _applicationTile('Plumber — Broadhurst', 'Pending', accent, JobsyColors.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget workerChat(Color accent) {
    return frame(
      label: 'MESSAGES',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JobsyColors.surface,
              border: Border(bottom: BorderSide(color: JobsyColors.border)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  child: Text('E', style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BuildRight BW',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: JobsyColors.textPrimary)),
                      Text('Electrician role',
                          style: TextStyle(
                              fontSize: 9, color: JobsyColors.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _chatBubble('Are you available Monday 8am?', false, accent),
                  const SizedBox(height: 8),
                  _chatBubble('Yes — I can be on site.', true, accent),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: JobsyColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JobsyColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 14, color: accent),
                          const SizedBox(width: 6),
                          const Text('Shared location',
                              style: TextStyle(fontSize: 10, color: JobsyColors.textSecondary)),
                        ],
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

  static Widget workerRoleSwitch(Color accent) {
    return frame(
      label: 'PROFILE → SUPPORT',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _settingsTile(Icons.swap_horiz_rounded, 'Switch to Employer',
                'Hire workers from the same account', accent, highlighted: true),
            _settingsTile(Icons.person_outline, 'My Info', null, accent),
            _settingsTile(Icons.play_circle_outline_rounded, 'App tour',
                'Replay the interactive onboarding', accent),
            _settingsTile(Icons.help_outline, 'Help & Support', null, accent),
          ],
        ),
      ),
    );
  }

  // ── Employer ─────────────────────────────────────────────────────────

  static Widget employerPortal(Color accent) {
    return frame(
      label: 'EMPLOYER PORTAL',
      child: Column(
        children: [
          JobsyAppBar(
            accentColor: accent,
            isEmployer: true,
            userName: 'Sarah',
            onLeadingPressed: () {},
            onProfileTap: () {},
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome back, Sarah',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: JobsyColors.textPrimary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(width: 3, height: 14, color: accent),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Your hiring dashboard',
                            style: TextStyle(
                                fontSize: 10, color: JobsyColors.textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: JobsyColors.employerGradient),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, color: JobsyColors.employerOnAccent, size: 20),
                        SizedBox(width: 8),
                        Text('Post a Job',
                            style: TextStyle(
                                color: JobsyColors.employerOnAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statBox('3', 'Active Jobs', accent)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox('12', 'Applications', JobsyColors.success)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _bottomNavPreview(accent, ['Home', 'Jobs', 'Wallet', 'Chat', 'Me'], 0),
        ],
      ),
    );
  }

  static Widget employerPostJob(Color accent) {
    return frame(
      label: 'POST JOB SCREEN',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Post a Job',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary)),
            const SizedBox(height: 12),
            _formLabel('Job title'),
            _formValue('Plumber needed'),
            const SizedBox(height: 8),
            _formLabel('Location'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.location_on, color: accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Job Location',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: JobsyColors.textTertiary)),
                        Text('Gaborone — GPS pin saved',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: JobsyColors.textPrimary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: JobsyColors.textTertiary, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 12),
            JobsyGradientButton(
              text: 'Publish listing',
              gradient: JobsyColors.employerGradient,
              height: 44,
              fontSize: 13,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  static Widget employerApplications(Color accent) {
    return frame(
      label: 'APPLICATIONS',
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plumber needed',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  _applicantCard('Thabo M.', '92% match', accent, rank: 1),
                  _applicantCard('Lerato K.', '78% match', accent, rank: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget employerChat(Color accent) => workerChat(accent);

  static Widget employerRoleSwitch(Color accent) {
    return frame(
      label: 'PROFILE → SUPPORT',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _settingsTile(Icons.swap_horiz_rounded, 'Switch to Worker',
                'Find gigs from the same account', accent, highlighted: true),
            _settingsTile(Icons.play_circle_outline_rounded, 'App tour',
                'Replay the interactive onboarding', accent),
            _settingsTile(Icons.help_outline, 'Help & Support', null, accent),
          ],
        ),
      ),
    );
  }

  /// Profile tab — same layout as [ProfileCoverHeader] + avatar badge.
  static Widget profileTab({
    required Color accent,
    required List<Color> headerGradient,
    required bool isEmployer,
  }) {
    final name = isEmployer ? 'Sarah Molefe' : 'Thabo Kgosi';
    return frame(
      label: 'PROFILE TAB',
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: headerGradient,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _coverEditChip('Add cover'),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _profileAvatarBadge(accent),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEmployer ? 'Emmis Construction' : 'Electrician · Gaborone',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _settingsTile(
              Icons.person_outline,
              'My Info',
              'Edit name, phone, skills & more',
              accent,
              highlighted: true,
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheets for avatar & cover — matches profile photo options.
  static Widget profilePhotoAndCover(Color accent) {
    return frame(
      label: 'PROFILE PHOTOS',
      child: Column(
        children: [
          Expanded(
            child: Center(child: _profileAvatarBadge(accent, size: 72)),
          ),
          Container(
            decoration: BoxDecoration(
              color: JobsyColors.surfaceLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Profile photo',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: JobsyColors.textSecondary)),
                const SizedBox(height: 6),
                _sheetTile(Icons.photo_camera, 'Take Photo', accent),
                _sheetTile(Icons.photo_library, 'Choose from Gallery', accent),
                const Divider(height: 16),
                const Text('Cover photo',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: JobsyColors.textSecondary)),
                const SizedBox(height: 6),
                _sheetTile(Icons.add_photo_alternate_outlined, 'Add cover', accent),
                _sheetTile(Icons.photo_camera_outlined, 'Take cover photo', accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// My Info editor — same fields as the profile edit dialog.
  static Widget profileEditForm({
    required Color accent,
    required bool isEmployer,
  }) {
    return frame(
      label: 'MY INFO',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  isEmployer ? 'Edit employer profile' : 'Edit worker profile',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: JobsyColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _formLabel('Full name'),
            _formValue(isEmployer ? 'Sarah Molefe' : 'Thabo Kgosi'),
            if (isEmployer) ...[
              _formLabel('Company name'),
              _formValue('Emmis Construction'),
              _formLabel('Business type'),
              _formValue('Construction'),
            ],
            _formLabel('Phone'),
            _formValue('+267 71 234 567'),
            _formLabel('Location'),
            _formValue('Gaborone, Block 8'),
            _formLabel('Bio'),
            _formValue(
              isEmployer
                  ? 'Hiring skilled trades across Gaborone…'
                  : 'Licensed electrician, 5 years experience…',
            ),
            if (!isEmployer) ...[
              _formLabel('Skills'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['Electrical', 'Wiring', 'Maintenance']
                    .map((s) => _chip(s, accent))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.75)]),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text('Save changes',
                  style: TextStyle(
                      color: JobsyColors.onRoleAccent(accent),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _coverEditChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 12, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92))),
        ],
      ),
    );
  }

  static Widget _profileAvatarBadge(Color accent, {double size = 56}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFCBD5E1)],
            ),
          ),
          child: CircleAvatar(
            radius: size / 2,
            backgroundColor: JobsyColors.surfaceElevated,
            child: Text('T',
                style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.7)]),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.camera_alt_rounded, size: 10, color: Colors.white),
          ),
        ),
      ],
    );
  }

  static Widget _sheetTile(IconData icon, String label, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: JobsyColors.textPrimary)),
        ],
      ),
    );
  }

  // ── Shared bits ──────────────────────────────────────────────────────

  static Widget _searchField(Color accent, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JobsyColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 16, color: JobsyColors.textSecondary),
          const SizedBox(width: 8),
          Text(hint,
              style: const TextStyle(fontSize: 11, color: JobsyColors.textTertiary)),
        ],
      ),
    );
  }

  static Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Widget _factRow(IconData icon, String label, String value, Color accent) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 8, color: JobsyColors.textTertiary)),
            Text(value,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: JobsyColors.textPrimary)),
          ],
        ),
        const Spacer(),
        if (icon == Icons.location_on_rounded)
          Icon(Icons.directions_rounded, size: 14, color: accent),
      ],
    );
  }

  static Widget _bottomNavPreview(Color accent, List<String> labels, int selected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: JobsyColors.navBarBackground,
        border: Border(top: BorderSide(color: JobsyColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: active ? 6 : 4, color: active ? accent : JobsyColors.border),
              const SizedBox(height: 2),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? accent : JobsyColors.textTertiary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  static Widget _tabPill(String label, bool selected, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? JobsyColors.onRoleAccent(accent) : JobsyColors.textSecondary,
        ),
      ),
    );
  }

  static Widget _applicationTile(
      String title, String status, Color accent, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JobsyColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(status,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
          ),
        ],
      ),
    );
  }

  static Widget _chatBubble(String text, bool isMe, Color accent) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? accent : JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: isMe ? null : Border.all(color: JobsyColors.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: isMe ? Colors.white : JobsyColors.textPrimary,
          ),
        ),
      ),
    );
  }

  static Widget _settingsTile(
    IconData icon,
    String title,
    String? subtitle,
    Color accent, {
    bool highlighted = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? accent.withValues(alpha: 0.08) : JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? accent.withValues(alpha: 0.35) : JobsyColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: JobsyColors.textPrimary)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 9, color: JobsyColors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: JobsyColors.textTertiary),
        ],
      ),
    );
  }

  static Widget _statBox(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JobsyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: JobsyColors.textSecondary)),
        ],
      ),
    );
  }

  static Widget _formLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(label,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: JobsyColors.textSecondary)),
    );
  }

  static Widget _formValue(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JobsyColors.border),
      ),
      child: Text(value,
          style: const TextStyle(fontSize: 11, color: JobsyColors.textPrimary)),
    );
  }

  static Widget _applicantCard(String name, String score, Color accent, {required int rank}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rank == 1 ? accent.withValues(alpha: 0.4) : JobsyColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Text('$rank',
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.textPrimary,
                    fontSize: 12)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: JobsyColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(score,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: JobsyColors.success)),
          ),
        ],
      ),
    );
  }
}
