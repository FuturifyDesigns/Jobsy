/// Heuristic helper that scores job applications for employers.
/// Uses profile data and application content — no external AI API required.
class ApplicationRankResult {
  final int score;
  final String tier;
  final List<String> pros;
  final List<String> cons;

  const ApplicationRankResult({
    required this.score,
    required this.tier,
    this.pros = const [],
    this.cons = const [],
  });

  bool get isStrong => score >= 75;
  bool get isGood => score >= 55 && score < 75;
  bool get isFair => score >= 35 && score < 55;
}

class ApplicationRankingService {
  ApplicationRankingService._();

  static ApplicationRankResult rank({
    required Map<String, dynamic> application,
    required Map<String, dynamic>? worker,
    String? jobDescription,
    String? jobTitle,
    List<String> requiredSkills = const [],
  }) {
    var score = 0;
    final pros = <String>[];
    final cons = <String>[];

    final rating = (worker?['rating'] as num?)?.toDouble() ?? 0;
    if (rating >= 4.5) {
      score += 25;
      pros.add('Excellent reviews (${rating.toStringAsFixed(1)}★ average)');
    } else if (rating >= 4.0) {
      score += 18;
      pros.add('Strong reviews (${rating.toStringAsFixed(1)}★ average)');
    } else if (rating >= 3.0) {
      score += 10;
      pros.add('Decent track record (${rating.toStringAsFixed(1)}★ average)');
    } else if (rating > 0) {
      score += 4;
    } else {
      cons.add('No ratings yet — newer worker');
    }

    final cover = application['cover_letter']?.toString().trim() ?? '';
    if (cover.length >= 120) {
      score += 22;
      pros.add('Thoughtful, detailed cover letter');
    } else if (cover.length >= 40) {
      score += 14;
      pros.add('Cover letter explains their fit');
    } else if (cover.isNotEmpty) {
      score += 6;
      cons.add('Cover letter is quite short');
    } else {
      cons.add('No cover letter provided');
    }

    final files = application['qualification_files'];
    final fileCount = files is List ? files.length : 0;
    if (fileCount >= 2) {
      score += 18;
      pros.add('Multiple qualification documents attached');
    } else if (fileCount == 1) {
      score += 12;
      pros.add('CV or certificate attached');
    } else {
      cons.add('No CV or certificates uploaded');
    }

    final refs = application['references_text']?.toString().trim() ?? '';
    if (refs.length >= 30) {
      score += 10;
      pros.add('References included');
    }

    final extra = application['additional_info']?.toString().trim() ?? '';
    if (extra.length >= 20) {
      score += 6;
      pros.add('Shared extra relevant details');
    }

    final experience = worker?['experience_level']?.toString().trim() ?? '';
    if (experience.isNotEmpty) {
      score += 8;
      pros.add('Experience level: $experience');
    } else {
      cons.add('Experience level not set on profile');
    }

    final location = worker?['location']?.toString().trim() ?? '';
    final jobLoc = jobDescription ?? jobTitle ?? '';
    if (location.isNotEmpty &&
        jobLoc.isNotEmpty &&
        _locationLikelyMatch(location, jobLoc)) {
      score += 8;
      pros.add('Location looks like a good match');
    }

    final workerSkills = (worker?['skills'] as List? ?? [])
        .map((s) => s.toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (requiredSkills.isNotEmpty && workerSkills.isNotEmpty) {
      final matched = <String>[];
      for (final req in requiredSkills) {
        final r = req.toString().trim().toLowerCase();
        if (workerSkills.any((w) => w == r || w.contains(r) || r.contains(w))) {
          matched.add(req.toString());
        }
      }
      if (matched.isNotEmpty) {
        score += (matched.length * 12).clamp(12, 36);
        pros.add('Skills match: ${matched.take(3).join(', ')}');
      } else {
        cons.add('Profile skills do not overlap job requirements');
      }
    }

    final hourly = (worker?['hourly_rate'] as num?)?.toDouble() ?? 0;
    if (hourly > 0) {
      score += 5;
    }

    score = score.clamp(0, 100);

    final tier = score >= 75
        ? 'Strong match'
        : score >= 55
            ? 'Good fit'
            : score >= 35
                ? 'Fair — review carefully'
                : 'Weak — missing key info';

    return ApplicationRankResult(
      score: score,
      tier: tier,
      pros: pros,
      cons: cons,
    );
  }

  static bool _locationLikelyMatch(String workerLoc, String jobText) {
    final w = workerLoc.toLowerCase();
    final j = jobText.toLowerCase();
    final wParts = w.split(RegExp(r'[,\s]+')).where((p) => p.length > 3);
    for (final part in wParts) {
      if (j.contains(part)) return true;
    }
    return false;
  }
}
