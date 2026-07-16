import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// Maps [PostgrestException] and other errors to short, user-facing text.
/// Never show raw exception strings to end users.
String friendlyErrorMessage(Object error) {
  if (error is PostgrestException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('job description is too short') ||
        msg.contains('minimum 20')) {
      return 'Please write a longer description (at least 20 characters) explaining what needs to be done.';
    }
    if (msg.contains('job title is too short') || msg.contains('minimum 3')) {
      return 'Job title is too short. Use at least 3 characters.';
    }
    if (msg.contains('title exceeds maximum')) {
      return 'Job title is too long. Shorten it to 200 characters or less.';
    }
    if (msg.contains('description exceeds maximum')) {
      return 'Description is too long. Use 5,000 characters or less.';
    }
    if (msg.contains('inappropriate language')) {
      return 'Please remove offensive language from your job text.';
    }
    if (msg.contains('budget_amount') || msg.contains('chk_budget')) {
      return 'Budget must be between P1 and P1,000,000.';
    }
    if (msg.contains('user_type cannot be changed') ||
        msg.contains('role cannot be changed directly')) {
      return 'Could not switch roles right now. Please try again.';
    }
    if (msg.contains('unauthorized profile creation')) {
      return 'Could not create your profile. Please sign in again.';
    }
    if (msg.contains('cannot apply to your own job')) {
      return 'You cannot apply to your own job posting.';
    }
    if (msg.contains('complete your profile before switching')) {
      return 'Complete your profile before switching roles.';
    }
    if (msg.contains('already in') && msg.contains('mode')) {
      return 'You are already in that role mode.';
    }
    if (msg.contains('wait') && msg.contains('before switching')) {
      final match =
          RegExp(r'wait (\d+) seconds?').firstMatch(error.message.toLowerCase());
      if (match != null) {
        return 'Please wait ${match.group(1)} seconds before switching roles again.';
      }
      return 'Please wait before switching roles again.';
    }
    if (msg.contains('hourly rate') && msg.contains('worker')) {
      return 'Set your hourly rate in My Info before switching to Worker mode.';
    }
    if (msg.contains('experience level') && msg.contains('worker')) {
      return 'Add your experience level in My Info before switching to Worker mode.';
    }
    if (msg.contains('job in progress') && msg.contains('switching')) {
      return 'You have a job in progress. Confirm completion or cancel it before switching to Worker mode.';
    }
    if (msg.contains('worker marked') && msg.contains('confirm completion')) {
      return 'A worker marked a job as done. Confirm completion in Employer mode before switching.';
    }
    if (msg.contains('hired worker') && msg.contains('active job')) {
      return 'You have a hired worker on an active job. Finish that job before switching to Worker mode.';
    }
    if (msg.contains('active job assignment') ||
        (msg.contains('complete it') && msg.contains('switching to employer'))) {
      return 'You have an active job assignment. Complete it before switching to Employer mode.';
    }
    if (msg.contains('switch to worker mode to mark')) {
      return 'Switch to Worker mode to mark a job as complete.';
    }
    if (msg.contains('switch to employer mode to confirm')) {
      return 'Switch to Employer mode to confirm job completion.';
    }
    if (msg.contains('use the in-app role switch after your profile is complete')) {
      return 'Your profile is already complete. Use Settings to switch roles.';
    }
    if (msg.contains('chk_no_self_rating') || msg.contains('self_rating')) {
      return 'You cannot rate yourself.';
    }
    if (msg.contains('phone') && msg.contains('check')) {
      return 'Please enter a valid phone number.';
    }
    if (msg.contains('message') && msg.contains('length')) {
      return 'Message is too long or empty.';
    }
    if (error.code == '42501' ||
        msg.contains('permission denied') ||
        msg.contains('row-level security')) {
      return 'You don\'t have permission to do that. Try signing in again.';
    }
    if (msg.contains('duplicate') || msg.contains('unique')) {
      return 'This record already exists. Try something different.';
    }
    if (msg.contains('function') && msg.contains('switch_user_role')) {
      return 'Role switching is not set up on the server yet. Run ROLE_SWITCH_HOTFIX.sql in Supabase.';
    }
    if (msg.contains('42703') || msg.contains('v_experience_level')) {
      return 'Role switch failed on the server. Run ROLE_SWITCH_HOTFIX.sql in Supabase SQL Editor.';
    }
    if (_looksLikeUserFacingServerMessage(error.message)) {
      return error.message.trim();
    }
    if (msg.contains('foreign key') || msg.contains('violates foreign key')) {
      return 'Something is missing or no longer available. Refresh and try again.';
    }
    return 'We couldn\'t complete that. Check your connection and try again.';
  }
  if (error is SocialSignInCancelledException) {
    return 'Sign-in was cancelled.';
  }
  if (error is SocialSignInNotConfiguredException) {
    return error.message;
  }
  if (error is AuthException) {
    return friendlyAuthErrorMessage(error);
  }
  if (error is FormatException) {
    return 'Please check the values you entered.';
  }

  final s = error.toString().toLowerCase();
  if (_looksLikeInternalOrDatabaseError(s)) {
    return 'We couldn\'t complete that. Check your connection and try again.';
  }
  if (s.contains('unsupported provider') ||
      (s.contains('validation_failed') && s.contains('provider'))) {
    return 'This sign-in option is not enabled yet. Try email instead.';
  }
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network') ||
      s.contains('timed out') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('handshake')) {
    return 'No internet connection. Check your network and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Maps Supabase Auth errors to clear, user-facing copy.
String friendlyAuthErrorMessage(AuthException error) {
  final msg = error.message.toLowerCase();

  if (msg.contains('already registered') ||
      msg.contains('already exists') ||
      msg.contains('user already registered') ||
      msg.contains('email address is already registered')) {
    return 'An account with this email already exists. Try signing in instead.';
  }
  if (msg.contains('invalid login credentials') ||
      msg.contains('invalid email or password')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  if (msg.contains('rate limit') || msg.contains('too many requests')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (msg.contains('password should be at least')) {
    return 'Password must be at least 6 characters.';
  }
  if (msg.contains('user not found')) {
    return 'No account found with that email address.';
  }
  if (msg.contains('signup is disabled')) {
    return 'New sign-ups are temporarily unavailable. Please try again later.';
  }
  if (msg.contains('provider') && msg.contains('not enabled')) {
    return 'This sign-in option is not enabled yet. Try email or another provider.';
  }
  if (msg.contains('validation_failed') && msg.contains('unsupported provider')) {
    return 'This sign-in option is not enabled in Supabase yet. Try email instead.';
  }
  if (msg.contains('invalid oauth') || msg.contains('oauth')) {
    return 'Sign-in failed. Please try again or use email.';
  }

  return 'Sign-in failed. Please check your details and try again.';
}

/// For [StreamBuilder.hasError] / [AsyncSnapshot.error] (may be null).
String friendlyStreamError(Object? error) {
  if (error == null) {
    return 'Something went wrong. Please try again.';
  }
  return friendlyErrorMessage(error);
}

bool _looksLikeInternalOrDatabaseError(String s) {
  return s.contains('postgrest') ||
      s.contains('pgrst') ||
      s.contains('postgres') ||
      s.contains('postgresql') ||
      s.contains('sqlstate') ||
      s.contains('violates') ||
      s.contains('relation ') ||
      s.contains(' relation') ||
      s.contains(' column ') ||
      s.contains('constraint ') ||
      s.contains('duplicate key') ||
      s.contains('foreign key') ||
      s.contains(' insert ') ||
      s.contains(' update ') ||
      s.contains('syntax error') ||
      s.contains('realtime') ||
      s.contains('storageexception') ||
      s.contains('.bucket') ||
      s.contains('object not found') ||
      s.contains('jwt') ||
      s.contains('invalid_api_key') ||
      s.contains('gotrue');
}

bool _looksLikeUserFacingServerMessage(String message) {
  final m = message.trim();
  if (m.isEmpty || m.length > 280) return false;
  final lower = m.toLowerCase();
  if (lower.contains('pgrst') ||
      lower.contains('sqlstate') ||
      lower.contains('syntax error') ||
      lower.contains('relation ') ||
      (lower.contains('column ') && lower.contains('does not exist')) ||
      lower.contains('undefined column') ||
      lower.contains('42703')) {
    return false;
  }
  return m.contains(' ') &&
      (lower.contains('switch') ||
          lower.contains('profile') ||
          lower.contains('worker') ||
          lower.contains('employer') ||
          lower.contains('job') ||
          lower.contains('wait') ||
          lower.contains('complete') ||
          lower.contains('hourly') ||
          lower.contains('experience'));
}
