import 'dart:convert';

import 'package:intl/intl.dart';

enum VacancyUrgency { open, comfortable, soon, critical, closed }

/// A parsed block of job description content.
class ExternalJobDescriptionSection {
  final String? heading;
  final List<String> paragraphs;
  final List<String> bullets;

  const ExternalJobDescriptionSection({
    this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });

  bool get isEmpty => paragraphs.isEmpty && bullets.isEmpty;
}

/// Formatting helpers for auto-imported web job listings.
class ExternalJobPresentation {
  ExternalJobPresentation._();

  static const _sectionHeaders = [
    'Company Description',
    'Job Description',
    'Job Summary',
    'About the Role',
    'About the Company',
    'About You',
    'Key Responsibilities',
    'Responsibilities',
    'Your Responsibilities',
    'What You Will Do',
    'Qualifications',
    'Requirements',
    'Skills & Experience',
    'Skills and Experience',
    'Experience',
    'Additional Information',
    'What We Offer',
    'Benefits',
    'How to Apply',
    'Missions',
  ];

  /// Any image URL from the import (often a small company logo).
  static String? imageUrl(Map<String, dynamic> job) => logoImageUrl(job);

  static String? logoImageUrl(Map<String, dynamic> job) {
    final raw = _rawImageUrl(job);
    if (raw == null) return null;
    return enhanceImageUrl(raw, forLogo: true);
  }

  static Map<String, dynamic>? metadataMap(Map<String, dynamic> job) {
    final meta = job['metadata'];
    if (meta is Map) return Map<String, dynamic>.from(meta);
    if (meta is String && meta.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(meta);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static bool hasDisplayImage(Map<String, dynamic> job) => _rawImageUrl(job) != null;

  static bool isLogoImage(Map<String, dynamic> job) {
    final raw = _rawImageUrl(job);
    if (raw == null) return false;
    final source = job['source']?.toString().toLowerCase() ?? '';
    // SerpAPI / Google Jobs only provides company thumbnails.
    if (source == 'google_jobs') return true;
    // Facebook posts rarely include usable logos in search snippets.
    if (source == 'facebook') return false;
    if (isLikelyLogoOrThumbnail(raw)) return true;
    return !_urlSuggestsLargePhoto(raw);
  }

  /// Full-width cover only when the URL is a real photo (≥400px), not a logo.
  static String? heroImageUrl(Map<String, dynamic> job) {
    if (isLogoImage(job)) return null;
    final raw = _rawImageUrl(job);
    if (raw == null) return null;
    return enhanceImageUrl(raw, forLogo: false);
  }

  static bool _urlSuggestsLargePhoto(String url) {
    final u = url.toLowerCase();
    final sizeMatch = RegExp(r'=s(\d+)').firstMatch(u);
    if (sizeMatch != null) {
      return (int.tryParse(sizeMatch.group(1)!) ?? 0) >= 400;
    }
    final whMatch = RegExp(r'=w(\d+)-h(\d+)').firstMatch(u);
    if (whMatch != null) {
      return (int.tryParse(whMatch.group(1)!) ?? 0) >= 400;
    }
    if (u.contains('/photo') ||
        u.contains('/hero') ||
        u.contains('banner') ||
        u.contains('cover')) {
      return true;
    }
    return false;
  }

  static String? _rawImageUrl(Map<String, dynamic> job) {
    final meta = metadataMap(job);
    if (meta != null) {
      for (final key in ['image_url', 'thumbnail', 'logo_url']) {
        final raw = meta[key]?.toString().trim();
        if (raw != null && raw.startsWith('http')) return raw;
      }
    }
    return null;
  }

  /// Google Jobs / RSS feeds usually ship 48–128px logos — not hero photos.
  static bool isLikelyLogoOrThumbnail(String url) {
    final u = url.toLowerCase();
    if (u.contains('encrypted-tbn') ||
        u.contains('tbn:') ||
        u.contains('gstatic.com') ||
        u.contains('logo') ||
        u.contains('favicon') ||
        u.contains('/icon')) {
      return true;
    }
    final sizeMatch = RegExp(r'=s(\d+)').firstMatch(u);
    if (sizeMatch != null) {
      final s = int.tryParse(sizeMatch.group(1)!) ?? 0;
      if (s > 0 && s < 400) return true;
    }
    final whMatch = RegExp(r'=w(\d+)-h(\d+)').firstMatch(u);
    if (whMatch != null) {
      final w = int.tryParse(whMatch.group(1)!) ?? 0;
      if (w > 0 && w < 400) return true;
    }
    return false;
  }

  /// Prefer higher-resolution variants when the source URL allows it.
  /// Never append size params to encrypted-tbn URLs (breaks the image load).
  static String enhanceImageUrl(String url, {bool forLogo = false}) {
    var u = url.trim();
    final lower = u.toLowerCase();

    if (lower.contains('encrypted-tbn') || lower.contains('tbn:')) {
      // Strip accidental =sXXX suffix from older imports (invalid on tbn URLs).
      return u.replaceAll(RegExp(r'=s\d+(-c)?$'), '');
    }

    if (lower.contains('googleusercontent.com')) {
      final target = forLogo ? 256 : 1200;
      u = u.replaceAll(RegExp(r'=s\d+(-c)?(?=&|$)'), '=s$target');
      if (!u.contains('=s')) {
        u = '$u=s$target';
      }
      return u;
    }

    if (!forLogo) {
      u = u.replaceAll(RegExp(r'=w\d+-h\d+'), '=w1200-h800');
    }
    return u;
  }

  /// Decode &#8217; &#x2019; &amp; and similar in imported feed text.
  static String decodeHtmlEntities(String text) {
    var result = text;

    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });

    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });

    const named = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&ndash;': '–',
      '&mdash;': '—',
      '&hellip;': '…',
      '&rsquo;': "'",
      '&lsquo;': "'",
      '&rdquo;': '"',
      '&ldquo;': '"',
    };
    for (final entry in named.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // Strip stray numeric fragments like "&#827" missing semicolon
    result = result.replaceAll(RegExp(r'&#\d{2,5}(?!;)'), '');

    return result;
  }

  static String cleanText(String raw) {
    return decodeHtmlEntities(raw.trim());
  }

  static ({String? email, String? phone, List<String> emails, List<String> phones})
      resolveContacts(Map<String, dynamic> job) {
    final description = cleanText(job['description']?.toString() ?? '');
    final title = cleanText(job['title']?.toString() ?? '');

    final emails = <String>{};
    final phones = <String>{};

    final storedEmail = job['contact_email']?.toString().trim();
    final storedPhone = job['contact_phone']?.toString().trim();
    if (storedEmail != null && storedEmail.isNotEmpty) emails.add(storedEmail);
    if (storedPhone != null && storedPhone.isNotEmpty) phones.add(storedPhone);

    for (final e in _extractEmails('$title $description')) {
      emails.add(e);
    }
    for (final p in _extractPhones('$title $description')) {
      phones.add(p);
    }

    final emailList = emails.toList();
    final phoneList = phones.toList();

    return (
      email: emailList.isNotEmpty ? emailList.first : null,
      phone: phoneList.isNotEmpty ? phoneList.first : null,
      emails: emailList,
      phones: phoneList,
    );
  }

  static List<String> _extractEmails(String text) {
    final re = RegExp(
      r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
      caseSensitive: false,
    );
    return re
        .allMatches(text)
        .map((m) => m.group(0)!.toLowerCase())
        .where((e) => !e.endsWith('.png') && !e.endsWith('.jpg'))
        .toSet()
        .toList();
  }

  static List<String> _extractPhones(String text) {
    final re = RegExp(
      r'(?:\+267|267)?[\s\-]?(?:7[1-8]|3[12])[\s\-]?\d{3}[\s\-]?\d{4}|\b\d{3}[\s\-]?\d{4}\b',
    );
    return re
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim())
        .toSet()
        .toList();
  }

  static String? jobTypeLabel(Map<String, dynamic> job) {
    final meta = job['metadata'];
    if (meta is Map) {
      final raw = meta['job_type']?.toString().trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return null;
  }

  static String cleanDescription(String raw) {
    var text = cleanText(raw);
    if (text.isEmpty) return '';

    text = text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n[ \t]+'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  /// Normalize run-on Google Jobs / RSS text into structured line breaks.
  static String normalizeDescription(String raw) {
    var text = cleanDescription(raw);
    if (text.isEmpty) return '';

    // "Key Responsibilities Assist with..." → header on its own line
    for (final header in _sectionHeaders) {
      final escaped = RegExp.escape(header);
      text = text.replaceAllMapped(
        RegExp('$escaped\\s*:', caseSensitive: false),
        (_) => '\n\n$header:\n',
      );
      text = text.replaceAllMapped(
        RegExp('$escaped(?=[A-Z])', caseSensitive: false),
        (_) => '\n\n$header\n',
      );
    }

    // Label: value patterns common in RSS listings
    const inlineLabels = [
      'Type',
      'Location',
      'Category',
      'Closing Date',
      'Email',
      'Submit',
    ];
    for (final label in inlineLabels) {
      text = text.replaceAllMapped(
        RegExp('(?<=[a-z\\.])\\s*$label:\\s*', caseSensitive: false),
        (_) => '\n$label: ',
      );
    }

    // Period immediately followed by capital → new sentence / bullet line
    text = text.replaceAllMapped(RegExp(r'\.(?=[A-Z])'), (_) => '.\n');

    // Lowercase letter glued to next sentence ("supervisorsAssist")
    text = text.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => '\n');

    // Explicit bullet characters
    text = text.replaceAll(RegExp(r'\s*[•·▪]\s*'), '\n• ');

    // Collapse whitespace per line, restore paragraph gaps
    text = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  static List<ExternalJobDescriptionSection> parseDescriptionSections(String raw) {
    final normalized = normalizeDescription(raw);
    if (normalized.isEmpty) return [];

    final chunks = normalized.split(RegExp(r'\n{2,}')).map((c) => c.trim()).where((c) => c.isNotEmpty);
    final sections = <ExternalJobDescriptionSection>[];

    for (final chunk in chunks) {
      final lines = chunk.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;

      String? heading;
      var bodyLines = lines;

      final first = lines.first;
      final headerMatch = _matchSectionHeader(first);
      if (headerMatch != null) {
        heading = headerMatch;
        bodyLines = lines.length > 1 ? lines.sublist(1) : [];
        if (bodyLines.isEmpty && first.length > headerMatch.length + 1) {
          bodyLines = [first.substring(headerMatch.length).trim()];
        }
      } else if (_isSectionHeaderLine(first)) {
        heading = first.replaceAll(RegExp(r':\s*$'), '');
        bodyLines = lines.length > 1 ? lines.sublist(1) : [];
      }

      final bullets = <String>[];
      final paragraphs = <String>[];

      for (final line in bodyLines) {
        final bulletText = _stripBulletPrefix(line);
        if (_looksLikeBulletLine(line)) {
          bullets.add(bulletText);
        } else if (_shouldSplitIntoBullets(line)) {
          bullets.addAll(_splitIntoBulletCandidates(line));
        } else {
          paragraphs.add(line);
        }
      }

      // Merge short verb-led paragraphs into bullets for responsibility sections
      if (_headingImpliesList(heading) && paragraphs.length > 1) {
        for (final p in paragraphs) {
          if (_startsLikeResponsibility(p) && p.length < 220) {
            bullets.add(p);
          }
        }
        paragraphs.removeWhere((p) => _startsLikeResponsibility(p) && p.length < 220);
      }

      if (heading == null && bullets.isEmpty && paragraphs.length == 1) {
        final only = paragraphs.first;
        if (_shouldSplitIntoBullets(only)) {
          sections.add(ExternalJobDescriptionSection(bullets: _splitIntoBulletCandidates(only)));
          continue;
        }
      }

      sections.add(ExternalJobDescriptionSection(
        heading: heading,
        paragraphs: paragraphs,
        bullets: bullets,
      ));
    }

    return sections.where((s) => !s.isEmpty).toList();
  }

  static List<String> descriptionBlocks(String raw) {
    final sections = parseDescriptionSections(raw);
    if (sections.isEmpty) return [];

    final blocks = <String>[];
    for (final section in sections) {
      if (section.heading != null) blocks.add(section.heading!);
      blocks.addAll(section.paragraphs);
      if (section.bullets.isNotEmpty) {
        blocks.add(section.bullets.map((b) => '• $b').join('\n'));
      }
    }
    return blocks;
  }

  static bool looksLikeBulletBlock(String block) {
    final lines = block.split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.length < 2) return false;
    return lines.every((l) => RegExp(r'^[•\-\*–]\s').hasMatch(l.trim()));
  }

  static List<String> bulletItems(String block) {
    return block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.replaceFirst(RegExp(r'^[•\-\*–]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static String? postedLabel(Map<String, dynamic> job) {
    final meta = job['metadata'];
    if (meta is Map) {
      final label = meta['posted_label']?.toString().trim();
      if (label != null && label.isNotEmpty) return label;
    }

    final raw = job['posted_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;

    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inDays == 0) return 'Posted today';
    if (diff.inDays == 1) return 'Posted yesterday';
    if (diff.inDays < 7) return 'Posted ${diff.inDays} days ago';
    if (diff.inDays < 30) return 'Posted ${(diff.inDays / 7).floor()} weeks ago';
    return 'Posted ${DateFormat('d MMM yyyy').format(local)}';
  }

  static String companyInitial(String? company) {
    final name = company?.trim();
    if (name == null || name.isEmpty) return 'J';
    return name[0].toUpperCase();
  }

  static String shortSummary(String raw, {int maxLength = 120}) {
    final clean = normalizeDescription(raw).replaceAll('\n', ' ');
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength).trimRight()}…';
  }

  /// When the vacancy closes (end of closing day, local time).
  static DateTime? expiresAt(Map<String, dynamic> job) {
    final raw = job['expires_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static String? closingDateLabel(Map<String, dynamic> job) {
    final meta = job['metadata'];
    if (meta is Map) {
      final label = meta['closing_label']?.toString().trim();
      if (label != null && label.isNotEmpty) return label;
    }
    final expires = expiresAt(job);
    if (expires == null) return null;
    return DateFormat('d MMM yyyy').format(expires);
  }

  static bool isExpired(Map<String, dynamic> job, {DateTime? now}) {
    now ??= DateTime.now();
    final expires = expiresAt(job);
    if (expires == null) return false;
    return !now.isBefore(expires);
  }

  static Duration? timeRemaining(Map<String, dynamic> job, {DateTime? now}) {
    now ??= DateTime.now();
    final expires = expiresAt(job);
    if (expires == null) return null;
    if (!now.isBefore(expires)) return Duration.zero;
    return expires.difference(now);
  }

  /// Live countdown label, e.g. "12 days left", "Closes in 4h".
  static String vacancyCountdownLabel(Map<String, dynamic> job, {DateTime? now}) {
    now ??= DateTime.now();
    final remaining = timeRemaining(job, now: now);
    if (remaining == null) return 'Open vacancy';
    if (remaining <= Duration.zero) return 'Closed';

    if (remaining.inDays > 1) return '${remaining.inDays} days left';
    if (remaining.inDays == 1) return '1 day left';
    if (remaining.inHours > 1) return '${remaining.inHours} hours left';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes} min left';
    return 'Closes soon';
  }

  static VacancyUrgency vacancyUrgency(Map<String, dynamic> job, {DateTime? now}) {
    final remaining = timeRemaining(job, now: now);
    if (remaining == null) return VacancyUrgency.open;
    if (remaining <= Duration.zero) return VacancyUrgency.closed;
    if (remaining.inDays <= 2) return VacancyUrgency.critical;
    if (remaining.inDays <= 7) return VacancyUrgency.soon;
    return VacancyUrgency.comfortable;
  }

  static String? _matchSectionHeader(String line) {
    final trimmed = line.trim();
    for (final header in _sectionHeaders) {
      if (trimmed.toLowerCase() == header.toLowerCase()) return header;
      if (trimmed.toLowerCase() == '${header.toLowerCase()}:') return header;
      if (trimmed.toLowerCase().startsWith(header.toLowerCase()) &&
          trimmed.length > header.length) {
        final next = trimmed[header.length];
        if (next == ':' || next == ' ' || _isUpperCase(next)) return header;
      }
    }
    return null;
  }

  static bool _isSectionHeaderLine(String line) {
    return _matchSectionHeader(line) != null;
  }

  static bool _isUpperCase(String char) {
    return char == char.toUpperCase() && char != char.toLowerCase();
  }

  static bool _looksLikeBulletLine(String line) {
    return RegExp(r'^[•\-\*–]\s').hasMatch(line);
  }

  static String _stripBulletPrefix(String line) {
    return line.replaceFirst(RegExp(r'^[•\-\*–]\s*'), '').trim();
  }

  static bool _headingImpliesList(String? heading) {
    if (heading == null) return false;
    final h = heading.toLowerCase();
    return h.contains('responsibilit') ||
        h.contains('requirement') ||
        h.contains('qualification') ||
        h.contains('mission') ||
        h.contains('skill') ||
        h.contains('what you');
  }

  static bool _startsLikeResponsibility(String text) {
    return RegExp(
      r'^(Assist|Perform|Maintain|Coordinate|Utilize|Support|Ensure|Provide|Prepare|Review|Load|Unload|Help|Manage|Develop|Handle|Work|Report|Follow|Operate|Deliver|Monitor|Conduct|Participate|Ability|Must|Should|Experience|Physical|Willing|Reliable|Previous|Botswana|Only|Submit|Email)\b',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  static bool _shouldSplitIntoBullets(String text) {
    if (text.length < 140) return false;
    if (_looksLikeBulletLine(text)) return false;
    final parts = _splitIntoBulletCandidates(text);
    return parts.length >= 3 && parts.every((p) => p.length < 220);
  }

  static List<String> _splitIntoBulletCandidates(String text) {
    final results = <String>[];

    // Split on period + space before a responsibility-style opener
    final pattern = RegExp(
      r'(?<=[\.!?])\s*(?=(Assist|Perform|Maintain|Coordinate|Utilize|Support|Ensure|Provide|Prepare|Review|Load|Unload|Help|Manage|Develop|Handle|Work|Report|Follow|Operate|Deliver|Monitor|Conduct|Participate|Physical|Willing|Reliable|Previous|Must|Should|Experience|Ability|Only|Submit|Email|CV|Botswana)\b)',
      caseSensitive: false,
    );

    var parts = text.split(pattern).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) {
      parts = text
          .split(RegExp(r'(?<=[a-z])(?=[A-Z])'))
          .map((p) => p.trim())
          .where((p) => p.length > 12)
          .toList();
    }

    for (var part in parts) {
      part = part.replaceAll(RegExp(r'^[\.\s]+'), '').trim();
      if (part.isEmpty) continue;
      if (part.length > 8) results.add(part);
    }

    return results;
  }
}
