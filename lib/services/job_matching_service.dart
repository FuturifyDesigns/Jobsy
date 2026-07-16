/// Skill / location matching between workers and jobs (no external AI).
class JobMatchResult {
  final int score;
  final List<String> matchedSkills;
  final bool locationMatch;

  const JobMatchResult({
    required this.score,
    this.matchedSkills = const [],
    this.locationMatch = false,
  });

  bool get isStrong => score >= 70;
  bool get isGood => score >= 45;
  String get label {
    if (score >= 70) return 'Great match';
    if (score >= 45) return 'Good match';
    if (score >= 25) return 'Possible match';
    return '';
  }
}

class JobMatchingService {
  JobMatchingService._();

  static List<String> _normalizeSkills(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  static bool locationsLikelyMatch(String? a, String? b) {
    final left = a?.trim().toLowerCase() ?? '';
    final right = b?.trim().toLowerCase() ?? '';
    if (left.isEmpty || right.isEmpty) return false;
    if (left.contains(right) || right.contains(left)) return true;
    for (final part in left.split(RegExp(r'[,\s]+'))) {
      if (part.length > 3 && right.contains(part)) return true;
    }
    for (final part in right.split(RegExp(r'[,\s]+'))) {
      if (part.length > 3 && left.contains(part)) return true;
    }
    return false;
  }

  static JobMatchResult scoreJobForWorker({
    required Map<String, dynamic> job,
    List<String> workerSkills = const [],
    String? workerLocation,
    String? workerBio,
  }) {
    final jobSkills = _normalizeSkills(job['required_skills']);
    final matched = <String>[];
    var score = 0;

    for (final js in jobSkills) {
      for (final ws in workerSkills) {
        if (js == ws || js.contains(ws) || ws.contains(js)) {
          matched.add(js);
          score += 22;
          break;
        }
      }
    }

    final jobLoc = job['location']?.toString();
    final locMatch = locationsLikelyMatch(workerLocation, jobLoc);
    if (locMatch) score += 18;

    final hay = '${workerBio ?? ''} ${workerSkills.join(' ')}'.toLowerCase();
    final category = job['category']?.toString().toLowerCase() ?? '';
    if (category.isNotEmpty && hay.contains(category)) score += 10;

    final title = job['title']?.toString().toLowerCase() ?? '';
    for (final ws in workerSkills) {
      if (ws.length > 3 && title.contains(ws)) score += 8;
    }

    if (jobSkills.isEmpty && workerSkills.isNotEmpty && score < 20 && locMatch) {
      score += 15;
    }

    return JobMatchResult(
      score: score.clamp(0, 100),
      matchedSkills: matched.toSet().toList(),
      locationMatch: locMatch,
    );
  }

  static JobMatchResult scoreWorkerForJob({
    required Map<String, dynamic>? worker,
    required Map<String, dynamic> job,
  }) {
    final skills = _normalizeSkills(worker?['skills']);
    return scoreJobForWorker(
      job: job,
      workerSkills: skills,
      workerLocation: worker?['location']?.toString(),
      workerBio: worker?['bio']?.toString(),
    );
  }
}
