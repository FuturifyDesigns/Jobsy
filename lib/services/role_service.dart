import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/colors.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../config/navigator_key.dart';
import '../utils/error_messages.dart';
import '../widgets/role_switch_cooldown.dart';
import '../widgets/role_switch_overlay.dart';

/// Summary of in-flight work that affects whether a role switch is allowed.
class RoleEngagementSummary {
  final bool hasEmployerBlock;
  final String? employerBlockReason;
  final bool hasWorkerBlock;
  final String? workerBlockReason;
  final List<String> warnings;

  const RoleEngagementSummary({
    this.hasEmployerBlock = false,
    this.employerBlockReason,
    this.hasWorkerBlock = false,
    this.workerBlockReason,
    this.warnings = const [],
  });
}

/// Result of pre-switch validation (client-side checks before calling RPC).
class RoleSwitchValidation {
  final bool allowed;
  final String? blockReason;
  final List<String> warnings;

  const RoleSwitchValidation({
    required this.allowed,
    this.blockReason,
    this.warnings = const [],
  });
}

/// Thrown when role switch is blocked by validation or the server.
class RoleSwitchException implements Exception {
  final String message;
  RoleSwitchException(this.message);

  @override
  String toString() => message;
}

enum RoleSetupField {
  experienceLevel,
  hourlyRate,
  companyName,
  businessType,
}

/// Switches the signed-in user between worker and employer modes.
class RoleService {
  RoleService._();

  static const Duration _switchCooldown = Duration(seconds: 30);

  /// Seconds left before the user can switch roles again, or zero if ready.
  static Future<Duration?> getSwitchCooldownRemaining() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('last_role_switch_at')
        .eq('id', userId)
        .maybeSingle();

    final lastSwitchRaw = profile?['last_role_switch_at']?.toString();
    if (lastSwitchRaw == null) return Duration.zero;

    final lastSwitch = DateTime.tryParse(lastSwitchRaw)?.toUtc();
    if (lastSwitch == null) return Duration.zero;

    final elapsed = DateTime.now().toUtc().difference(lastSwitch);
    if (elapsed >= _switchCooldown) return Duration.zero;
    return _switchCooldown - elapsed;
  }

  static String formatSwitchCooldown(Duration remaining) {
    final totalSec = remaining.inSeconds.clamp(0, 9999);
    if (totalSec >= 60) {
      final minutes = totalSec ~/ 60;
      final seconds = totalSec % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return '${totalSec}s';
  }

  static bool isSwitchCooldownError(String message) {
    final msg = message.toLowerCase();
    return msg.contains('wait') &&
        (msg.contains('before switching') || msg.contains('switching roles'));
  }

  /// Blocks until cooldown ends or the user dismisses the countdown dialog.
  static Future<bool> waitForSwitchCooldown(BuildContext context) async {
    while (context.mounted) {
      final remaining = await getSwitchCooldownRemaining();
      if (remaining == null || remaining <= Duration.zero) return true;

      final ready = await RoleSwitchCooldownDialog.show(
        context,
        initialRemaining: remaining,
      );
      if (!context.mounted) return false;
      if (!ready) return false;

      final again = await getSwitchCooldownRemaining();
      if (again == null || again <= Duration.zero) return true;
    }
    return false;
  }

  static Future<void> showSwitchCooldownIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    final remaining = await getSwitchCooldownRemaining();
    if (remaining == null || remaining <= Duration.zero) return;
    await RoleSwitchCooldownDialog.show(
      context,
      initialRemaining: remaining,
    );
  }

  static Future<String?> getCurrentRole() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('user_type')
        .eq('id', userId)
        .maybeSingle();

    return profile?['user_type'] as String?;
  }

  static String oppositeRole(String role) {
    return role == AppConstants.userTypeEmployer
        ? AppConstants.userTypeWorker
        : AppConstants.userTypeEmployer;
  }

  static String roleLabel(String role) {
    return role == AppConstants.userTypeEmployer ? 'Employer' : 'Worker';
  }

  /// Worker-specific fields needed before applying (not required just to switch/browse).
  static Future<bool> isWorkerProfileReadyForApply() async {
    final missing = await missingSetupFields(AppConstants.userTypeWorker);
    return missing.isEmpty;
  }

  static Future<List<RoleSetupField>> missingSetupFields(String role) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const [];

    final profile = await Supabase.instance.client
        .from('profiles')
        .select(
          'experience_level, hourly_rate, company_name, business_type',
        )
        .eq('id', userId)
        .maybeSingle();

    if (profile == null) return const [];

    final missing = <RoleSetupField>[];
    if (role == AppConstants.userTypeWorker) {
      final experience = profile['experience_level']?.toString().trim() ?? '';
      final hourlyRate = (profile['hourly_rate'] as num?)?.toDouble() ?? 0;
      if (experience.isEmpty) missing.add(RoleSetupField.experienceLevel);
      if (hourlyRate <= 0) missing.add(RoleSetupField.hourlyRate);
    } else if (role == AppConstants.userTypeEmployer) {
      final company = profile['company_name']?.toString().trim() ?? '';
      final business = profile['business_type']?.toString().trim() ?? '';
      if (company.isEmpty) missing.add(RoleSetupField.companyName);
      if (business.isEmpty) missing.add(RoleSetupField.businessType);
    }
    return missing;
  }

  static Future<bool> isRoleSetupComplete(String role) async {
    final missing = await missingSetupFields(role);
    return missing.isEmpty;
  }

  static Future<bool> isEmployerProfileReadyForPost() async {
    final missing = await missingSetupFields(AppConstants.userTypeEmployer);
    return missing.isEmpty;
  }

  /// Human-readable hint when worker profile is incomplete for applying.
  static Future<String?> workerApplyBlockReason() async {
    if (await isWorkerProfileReadyForApply()) return null;
    return 'Complete your worker profile to apply for this job.';
  }

  /// Loads active jobs/applications that block or warn on role switch.
  static Future<RoleEngagementSummary> getEngagementSummary(String userId) async {
    final client = Supabase.instance.client;
    final warnings = <String>[];

    // ── Employer-side engagements ─────────────────────────────────────────
    String? employerBlockReason;

    final inProgressJobs = await client
        .from('jobs')
        .select('id, title')
        .eq('employer_id', userId)
        .eq('status', 'in_progress');

    if (inProgressJobs.isNotEmpty) {
      final title = inProgressJobs.first['title']?.toString() ?? 'a job';
      employerBlockReason =
          'You have a job in progress ("$title"). Confirm completion or cancel it before switching to Worker mode.';
    }

    if (employerBlockReason == null) {
      final awaitingConfirm = await client
          .from('job_applications')
          .select('id, job:jobs(title, status, employer_id)')
          .eq('worker_completed', true)
          .inFilter('status', ['accepted', 'in_progress']);

      for (final row in awaitingConfirm) {
        final job = row['job'] as Map<String, dynamic>?;
        if (job == null) continue;
        if (job['employer_id'] != userId) continue;
        final status = job['status']?.toString() ?? '';
        if (status == 'completed' || status == 'cancelled') continue;
        final title = job['title']?.toString() ?? 'a job';
        employerBlockReason =
            'A worker marked "$title" as done. Confirm completion in Employer mode before switching.';
        break;
      }
    }

    if (employerBlockReason == null) {
      final hiredApps = await client
          .from('job_applications')
          .select('id, status, job:jobs(id, title, employer_id, status)')
          .inFilter('status', ['accepted', 'in_progress']);

      for (final row in hiredApps) {
        final job = row['job'] as Map<String, dynamic>?;
        if (job == null || job['employer_id'] != userId) continue;
        final jobStatus = job['status']?.toString() ?? '';
        if (jobStatus != 'active' && jobStatus != 'in_progress') continue;
        final title = job['title']?.toString() ?? 'a job';
        employerBlockReason =
            'You have a hired worker on "$title". Finish that job before switching to Worker mode.';
        break;
      }
    }

    if (employerBlockReason == null) {
      final pendingReview = await client
          .from('job_applications')
          .select('id, job:jobs(title, employer_id, status)')
          .eq('status', 'pending');

      var pendingCount = 0;
      for (final row in pendingReview) {
        final job = row['job'] as Map<String, dynamic>?;
        if (job == null || job['employer_id'] != userId) continue;
        if (job['status']?.toString() == 'cancelled') continue;
        pendingCount++;
      }
      if (pendingCount > 0) {
        warnings.add(
          'You have $pendingCount pending application(s) to review. Switch back to Employer mode to respond.',
        );
      }

      final activeListings = await client
          .from('jobs')
          .select('id')
          .eq('employer_id', userId)
          .eq('status', 'active');
      if (activeListings.isNotEmpty) {
        warnings.add(
          'You have ${activeListings.length} open job listing(s). You can manage them after switching back.',
        );
      }
    }

    // ── Worker-side engagements ───────────────────────────────────────────
    String? workerBlockReason;

    final activeAssignments = await client
        .from('job_applications')
        .select('id, status, worker_completed, job:jobs(title, status)')
        .eq('worker_id', userId)
        .inFilter('status', ['accepted', 'in_progress']);

    for (final row in activeAssignments) {
      final job = row['job'] as Map<String, dynamic>?;
      if (job == null) continue;
      final jobStatus = job['status']?.toString() ?? '';
      if (jobStatus == 'completed' || jobStatus == 'cancelled') continue;

      final title = job['title']?.toString() ?? 'a job';
      final workerDone = row['worker_completed'] == true;

      if (!workerDone) {
        workerBlockReason =
            'You are working on "$title". Tap Complete Job in chat before switching to Employer mode.';
      } else {
        workerBlockReason =
            'You marked "$title" as done. Wait for the employer to confirm before switching to Employer mode.';
      }
      break;
    }

    if (workerBlockReason == null) {
      final pendingApps = await client
          .from('job_applications')
          .select('id')
          .eq('worker_id', userId)
          .eq('status', 'pending');
      if (pendingApps.isNotEmpty) {
        warnings.add(
          'You have ${pendingApps.length} pending application(s). Employers may respond while you are away.',
        );
      }
    }

    // Unrated completed jobs — warn only
    try {
      final myId = userId;
      final completedApps = await client
          .from('job_applications')
          .select('id, job_id, job:jobs(title, status)')
          .eq('worker_id', userId)
          .eq('status', 'completed');

      for (final app in completedApps) {
        final appId = app['id']?.toString();
        if (appId == null) continue;
        final rated = await client
            .from('ratings')
            .select('id')
            .eq('rater_id', myId)
            .eq('application_id', appId)
            .maybeSingle();
        if (rated == null) {
          final title = (app['job'] as Map?)?['title']?.toString() ?? 'a job';
          warnings.add('You have not rated "$title" yet. You can still rate from chat later.');
          break;
        }
      }
    } catch (_) {}

    return RoleEngagementSummary(
      hasEmployerBlock: employerBlockReason != null,
      employerBlockReason: employerBlockReason,
      hasWorkerBlock: workerBlockReason != null,
      workerBlockReason: workerBlockReason,
      warnings: warnings,
    );
  }

  /// Client-side validation before calling the server RPC.
  static Future<RoleSwitchValidation> validateSwitchTo(String targetRole) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return const RoleSwitchValidation(
        allowed: false,
        blockReason: 'You must be signed in to switch roles.',
      );
    }

    if (targetRole != AppConstants.userTypeEmployer &&
        targetRole != AppConstants.userTypeWorker) {
      return const RoleSwitchValidation(
        allowed: false,
        blockReason: 'Invalid role.',
      );
    }

    final profile = await Supabase.instance.client
        .from('profiles')
        .select(
          'user_type, is_profile_complete, hourly_rate, experience_level, last_role_switch_at',
        )
        .eq('id', userId)
        .maybeSingle();

    if (profile == null) {
      return const RoleSwitchValidation(
        allowed: false,
        blockReason: 'Profile not found. Try signing in again.',
      );
    }

    final current = profile['user_type'] as String?;
    final isComplete = profile['is_profile_complete'] as bool? ?? false;

    if (!isComplete) {
      return const RoleSwitchValidation(
        allowed: false,
        blockReason: 'Complete your profile before switching roles.',
      );
    }

    if (current == targetRole) {
      return RoleSwitchValidation(
        allowed: false,
        blockReason: 'You are already in ${roleLabel(targetRole)} mode.',
      );
    }

    final lastSwitchRaw = profile['last_role_switch_at']?.toString();
    if (lastSwitchRaw != null) {
      final lastSwitch = DateTime.tryParse(lastSwitchRaw)?.toUtc();
      if (lastSwitch != null) {
        final elapsed = DateTime.now().toUtc().difference(lastSwitch);
        if (elapsed < _switchCooldown) {
          final wait = _switchCooldown - elapsed;
          final waitSec = wait.inSeconds.clamp(1, _switchCooldown.inSeconds);
          return RoleSwitchValidation(
            allowed: false,
            blockReason:
                'You can switch again in ${formatSwitchCooldown(wait)} ($waitSec seconds).',
          );
        }
      }
    }

    final engagements = await getEngagementSummary(userId);

    if (targetRole == AppConstants.userTypeWorker &&
        engagements.hasEmployerBlock) {
      return RoleSwitchValidation(
        allowed: false,
        blockReason: engagements.employerBlockReason,
      );
    }

    if (targetRole == AppConstants.userTypeEmployer &&
        engagements.hasWorkerBlock) {
      return RoleSwitchValidation(
        allowed: false,
        blockReason: engagements.workerBlockReason,
      );
    }

    return RoleSwitchValidation(
      allowed: true,
      warnings: engagements.warnings,
    );
  }

  /// Server-validated role switch via RPC.
  static Future<String> switchRole(String targetRole) async {
    final validation = await validateSwitchTo(targetRole);
    if (!validation.allowed) {
      throw RoleSwitchException(
        validation.blockReason ?? 'Cannot switch roles right now.',
      );
    }

    try {
      final result = await Supabase.instance.client.rpc(
        'switch_user_role',
        params: {'p_target_role': targetRole},
      );
      return result as String;
    } on PostgrestException catch (e) {
      throw RoleSwitchException(friendlyErrorMessage(e));
    }
  }

  /// Full UI flow: confirm → switch → animated success → navigate.
  static Future<bool> confirmAndSwitch(
    BuildContext context, {
    required String targetRole,
    int initialTab = 0,
  }) async {
    if (!await waitForSwitchCooldown(context) || !context.mounted) {
      return false;
    }

    final targetLabel = roleLabel(targetRole);
    final accent = targetRole == AppConstants.userTypeEmployer
        ? JobsyColors.employerPrimary
        : JobsyColors.workerPrimary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JobsyColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Switch to $targetLabel mode?',
          style: const TextStyle(
            color: JobsyColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          targetRole == AppConstants.userTypeEmployer
              ? 'You\'ll post and manage jobs in Employer mode. We\'ll ask for any missing business details right after switching.'
              : 'You\'ll browse jobs in Worker mode. We\'ll ask for any missing details right after switching.',
          style: const TextStyle(
            color: JobsyColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: JobsyColors.onRoleAccent(accent),
              splashFactory: NoSplash.splashFactory,
            ),
            child: Text('Switch to $targetLabel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return false;

    RoleSwitchOverlay.showLoading(context, targetRole);

    try {
      await switchRoleServer(targetRole);
      if (!context.mounted) return false;

      await RoleSwitchOverlay.showSuccess(context, targetRole);

      final route = targetRole == AppConstants.userTypeEmployer
          ? AppRoutes.employerHome
          : AppRoutes.workerHome;

      final routeArgs = <String, dynamic>{'initialTab': initialTab};
      if (!await isRoleSetupComplete(targetRole)) {
        routeArgs['promptRoleSetup'] = true;
      }

      final navigator = navigatorKey.currentState;
      if (navigator == null) return false;

      navigator.pushNamedAndRemoveUntil(
        route,
        (route) => false,
        arguments: routeArgs,
      );
      return true;
    } on RoleSwitchException catch (e) {
      if (context.mounted) {
        RoleSwitchOverlay.dismiss(context);
        if (isSwitchCooldownError(e.message)) {
          await showSwitchCooldownIfNeeded(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: JobsyColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        RoleSwitchOverlay.dismiss(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
      return false;
    }
  }

  /// Server-only role switch (fast path — skips slow client engagement queries).
  static Future<String> switchRoleServer(String targetRole) async {
    try {
      final result = await Supabase.instance.client
          .rpc('switch_user_role', params: {'p_target_role': targetRole})
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw RoleSwitchException(
              'Role switch timed out. Check your connection and try again.',
            ),
          );
      return result as String;
    } on RoleSwitchException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[RoleService] switch_user_role failed: ${e.message}');
      throw RoleSwitchException(friendlyErrorMessage(e));
    }
  }

  /// Returns true if the current user owns this job posting (cannot apply).
  static bool isOwnJobPosting(String? employerId) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    return myId != null && employerId != null && myId == employerId;
  }

  /// Returns true if the user is currently in employer mode.
  static Future<bool> isEmployerMode() async {
    final role = await getCurrentRole();
    return role == AppConstants.userTypeEmployer;
  }

  /// Returns true if the user is currently in worker mode.
  static Future<bool> isWorkerMode() async {
    final role = await getCurrentRole();
    return role == AppConstants.userTypeWorker;
  }
}
