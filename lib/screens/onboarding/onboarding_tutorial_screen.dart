import 'package:flutter/material.dart';

import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../services/onboarding_tutorial_service.dart';
import '../../widgets/jobsy_pressable.dart';
import '../../widgets/modern_widgets.dart';
import '../../widgets/onboarding_ui_previews.dart';

class _TutorialPage {
  final IconData icon;
  final String title;
  final String body;
  final String highlight;
  final Widget Function(Color accent) buildPreview;

  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.highlight,
    required this.buildPreview,
  });
}

/// Interactive first-run / replay walkthrough using real Jobsy UI previews.
class OnboardingTutorialScreen extends StatefulWidget {
  final String userType;
  final bool isReplay;

  const OnboardingTutorialScreen({
    super.key,
    required this.userType,
    this.isReplay = false,
  });

  @override
  State<OnboardingTutorialScreen> createState() =>
      _OnboardingTutorialScreenState();
}

class _OnboardingTutorialScreenState extends State<OnboardingTutorialScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  late final AnimationController _pulseCtrl;

  bool get _isEmployer => widget.userType == AppConstants.userTypeEmployer;

  List<Color> get _accentGradient =>
      _isEmployer ? JobsyColors.employerGradient : JobsyColors.workerGradient;

  Color get _accent =>
      _isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;

  late final List<_TutorialPage> _pages =
      _isEmployer ? _employerPages : _workerPages;

  static List<_TutorialPage> get _workerPages => [
        _TutorialPage(
          icon: Icons.dashboard_rounded,
          title: 'Your worker portal',
          body:
              'This is the real Jobsy home — browse local jobs, track applications, chat with employers, and manage your profile.',
          highlight: 'Bottom tabs: Find Jobs · My Jobs · Messages · Profile',
          buildPreview: OnboardingUiPreviews.workerPortal,
        ),
        _TutorialPage(
          icon: Icons.work_outline_rounded,
          title: 'Browse & apply locally',
          body:
              'Job cards show employer, pay, location, and skill-match scores. Tap any listing to view details and apply.',
          highlight: 'Find Jobs tab — same cards you see in the app',
          buildPreview: OnboardingUiPreviews.workerLocalJobCard,
        ),
        _TutorialPage(
          icon: Icons.public_rounded,
          title: 'Web Jobs feed',
          body:
              'Auto-imported listings from Google Jobs and boards appear here with vacancy countdowns and company info.',
          highlight: 'Tap the Web Jobs banner from Find Jobs',
          buildPreview: OnboardingUiPreviews.workerWebJobs,
        ),
        _TutorialPage(
          icon: Icons.description_outlined,
          title: 'Job details & directions',
          body:
              'Full role info, closing dates, and tap-to-open Google Maps for the job site. GPS-pinned posts open the exact location.',
          highlight: 'Location row opens Maps for directions',
          buildPreview: OnboardingUiPreviews.workerJobDetail,
        ),
        _TutorialPage(
          icon: Icons.assignment_outlined,
          title: 'Track your applications',
          body:
              'My Jobs shows every role you applied for — status, employer replies, and quick access back to listings.',
          highlight: 'My Jobs tab — pending, accepted & closed',
          buildPreview: OnboardingUiPreviews.workerMyJobs,
        ),
        _TutorialPage(
          icon: Icons.forum_rounded,
          title: 'Chat with employers',
          body:
              'Real messaging UI — discuss scope, share documents, voice notes, and live location on site.',
          highlight: 'Messages tab — same chat you use on jobs',
          buildPreview: OnboardingUiPreviews.workerChat,
        ),
        _TutorialPage(
          icon: Icons.account_circle_outlined,
          title: 'Your profile header',
          body:
              'The Profile tab uses the same cover header as the app. Add a cover photo from the top-left button and stand out to employers.',
          highlight: 'Profile tab → Add cover (top-left)',
          buildPreview: (accent) => OnboardingUiPreviews.profileTab(
            accent: accent,
            headerGradient: JobsyColors.workerGradient,
            isEmployer: false,
          ),
        ),
        _TutorialPage(
          icon: Icons.camera_alt_rounded,
          title: 'Profile & cover photos',
          body:
              'Tap the camera badge on your avatar to take or pick a profile photo. Use the same flow for cover images from the header.',
          highlight: 'Avatar camera badge · Add cover button',
          buildPreview: OnboardingUiPreviews.profilePhotoAndCover,
        ),
        _TutorialPage(
          icon: Icons.edit_note_rounded,
          title: 'Edit your profile',
          body:
              'Open My Info on Profile to update your name, phone, location, bio, and skills. A complete profile gets better match scores.',
          highlight: 'Profile → My Info → Save changes',
          buildPreview: (accent) => OnboardingUiPreviews.profileEditForm(
            accent: accent,
            isEmployer: false,
          ),
        ),
        _TutorialPage(
          icon: Icons.swap_horiz_rounded,
          title: 'Switch roles anytime',
          body:
              'Need to hire? Profile → Switch to Employer. Replay this tour anytime from Profile → App tour.',
          highlight: 'Profile → Switch to Employer',
          buildPreview: OnboardingUiPreviews.workerRoleSwitch,
        ),
      ];

  static List<_TutorialPage> get _employerPages => [
        _TutorialPage(
          icon: Icons.apartment_rounded,
          title: 'Your hiring desk',
          body:
              'The employer home you use every day — post jobs, see stats, and jump to applications from one dashboard.',
          highlight: 'Home tab — Post a Job is your main action',
          buildPreview: OnboardingUiPreviews.employerPortal,
        ),
        _TutorialPage(
          icon: Icons.post_add_rounded,
          title: 'Post a role',
          body:
              'Same post-job form as the app: title, pay, skills, photos, and GPS location pinning for site directions.',
          highlight: 'Use GPS for an exact workplace pin',
          buildPreview: OnboardingUiPreviews.employerPostJob,
        ),
        _TutorialPage(
          icon: Icons.people_alt_rounded,
          title: 'Ranked applicants',
          body:
              'Review applications sorted by match score. Open profiles, accept the best fit, and message instantly.',
          highlight: 'My Jobs → tap a listing → Applications',
          buildPreview: OnboardingUiPreviews.employerApplications,
        ),
        _TutorialPage(
          icon: Icons.forum_rounded,
          title: 'Chat & coordinate',
          body:
              'Real messaging UI — discuss scope, share documents, voice notes, and live location on site.',
          highlight: 'Messages tab — same chat you use on jobs',
          buildPreview: OnboardingUiPreviews.employerChat,
        ),
        _TutorialPage(
          icon: Icons.account_circle_outlined,
          title: 'Your company profile',
          body:
              'Employers get the same Profile tab with a cover header. Add your brand cover and logo so workers trust your listings.',
          highlight: 'Profile tab → Add cover (top-left)',
          buildPreview: (accent) => OnboardingUiPreviews.profileTab(
            accent: accent,
            headerGradient: JobsyColors.employerGradient,
            isEmployer: true,
          ),
        ),
        _TutorialPage(
          icon: Icons.camera_alt_rounded,
          title: 'Logo & cover photos',
          body:
              'Tap the camera on your avatar for a company photo. Use Add cover on the header for a branded banner workers will see.',
          highlight: 'Avatar camera badge · Add cover button',
          buildPreview: OnboardingUiPreviews.profilePhotoAndCover,
        ),
        _TutorialPage(
          icon: Icons.edit_note_rounded,
          title: 'Edit company details',
          body:
              'Profile → My Info lets you update your name, company, business type, phone, location, and bio.',
          highlight: 'Profile → My Info → Save changes',
          buildPreview: (accent) => OnboardingUiPreviews.profileEditForm(
            accent: accent,
            isEmployer: true,
          ),
        ),
        _TutorialPage(
          icon: Icons.swap_horiz_rounded,
          title: 'Switch when you need work',
          body:
              'Looking for gigs? Profile → Switch to Worker. Replay this tour from Profile → App tour.',
          highlight: 'Profile → Switch to Worker',
          buildPreview: OnboardingUiPreviews.employerRoleSwitch,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish({bool showCelebration = false}) async {
    if (!widget.isReplay) {
      await OnboardingTutorialService.markCompleted();
    }
    if (!mounted) return;

    if (showCelebration) {
      await _showCompletionDialog();
      if (!mounted) return;
    }

    if (widget.isReplay) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacementNamed(
      context,
      OnboardingTutorialService.homeRouteFor(widget.userType),
    );
  }

  Future<void> _showCompletionDialog() async {
    final title = _isEmployer ? "You're ready to hire!" : "You're all set!";
    final message = _isEmployer
        ? 'Post your first role and connect with skilled talent across Botswana. Your hiring desk is live — go make it happen.'
        : 'Botswana\'s best gigs are waiting for you. Update your profile, apply with confidence, and land your next role.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: JobsyColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _accentGradient),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: JobsyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: JobsyColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: JobsyGradientButton(
                text: widget.isReplay ? 'Nice!' : "Let's go",
                gradient: _accentGradient,
                onPressed: () => Navigator.pop(ctx),
                height: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _next() {
    if (_pageIndex >= _pages.length - 1) {
      _finish(showCelebration: true);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_pageIndex <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _pageIndex >= _pages.length - 1;

    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  if (widget.isReplay)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: JobsyColors.textSecondary,
                    )
                  else
                    JobsyPressable(
                      onPressed: _finish,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: JobsyColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      widget.isReplay ? 'REPLAY' : 'ONBOARDING',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_pageIndex + 1}/${_pages.length}',
                    style: const TextStyle(
                      color: JobsyColors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  switchInCurve: Curves.easeOutCubic,
                                  child: KeyedSubtree(
                                    key: ValueKey(index),
                                    child: page.buildPreview(_accent),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(page.icon, color: _accent, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    page.title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: JobsyColors.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              page.body,
                              style: const TextStyle(
                                fontSize: 14,
                                color: JobsyColors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: JobsyColors.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _accent.withValues(
                                    alpha: 0.22 + _pulseCtrl.value * 0.18,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.touch_app_rounded,
                                      size: 18, color: _accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      page.highlight,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _accent.withValues(alpha: 0.95),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _pageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? _accent : JobsyColors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                children: [
                  if (_pageIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previous,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JobsyColors.textSecondary,
                          side: const BorderSide(color: JobsyColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_pageIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: _pageIndex > 0 ? 2 : 1,
                    child: JobsyGradientButton(
                      text: isLast
                          ? (widget.isReplay ? 'Done' : 'Get Started')
                          : 'Continue',
                      gradient: _accentGradient,
                      onPressed: _next,
                      height: 52,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
