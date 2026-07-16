class AppConstants {
  static const String appName = 'Jobsy';
  static const String appTagline = 'Find work or hire workers near you';
  static const String builtBy = 'Built by Futurify Designs';

  /// RFC-5322-inspired email regex — catches the vast majority of bad inputs.
  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+"
    r'@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)'
    r'+$',
  );

  /// Returns an error string if [email] is invalid, or null if it is valid.
  static String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email.trim())) return 'Enter a valid email address';
    return null;
  }

  /// Single source of truth for job categories used across post, browse, and filters.
  static const List<String> jobCategories = [
    'Construction',
    'Cleaning',
    'Plumbing',
    'Electrical',
    'Carpentry',
    'Painting',
    'Gardening',
    'Welding',
    'Masonry',
    'Roofing',
    'General Labor',
    'Administrative',
    'Retail & Sales',
    'Hospitality',
    'Security',
    'Transport & Driving',
    'Healthcare',
    'Technology',
    'Finance',
    'Other',
  ];

  static const String userTypeEmployer = 'employer';
  static const String userTypeWorker = 'worker';

  /// Title for the auto-imported external job listings page.
  static const String webJobsFeedTitle = 'Web Jobs';
  static const String webJobsFeedSubtitle =
      'Imported from job sites · Apply on the original website';

  static const String authResetPasswordRedirect =
      'https://futurifydesigns.github.io/Jobsy/reset-password.html';

  /// OAuth / magic-link callback (Google PKCE fallback, email links).
  static const String authLoginCallbackRedirect = 'jobsy://login-callback';

  /// Email confirmation lands on GitHub Pages.
  static const String authEmailVerifiedRedirect =
      'https://futurifydesigns.github.io/Jobsy/';

  /// Public site (legal pages + auth Pages).
  static const String websiteUrl = 'https://futurifydesigns.github.io/Jobsy';

  static const String supportEmail = 'futurifydesigns@gmail.com';
  static const String dataProtectionAct = 'Data Protection Act, 2024 (Act No. 18 of 2024)';
}
