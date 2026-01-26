class SRSData {
  final double easinessFactor;
  final int interval;
  final int repetitions;
  final String? nextReviewDate;
  final String? lastReviewDate;
  final int familiarityLevel;

  SRSData({
    required this.easinessFactor,
    required this.interval,
    required this.repetitions,
    this.nextReviewDate,
    this.lastReviewDate,
    required this.familiarityLevel,
  });

  static SRSData defaultData() {
    return SRSData(
      easinessFactor: 2.5,
      interval: 0,
      repetitions: 0,
      nextReviewDate: null,
      lastReviewDate: null,
      familiarityLevel: 1,
    );
  }
}

class ReviewResult {
  final double newEasinessFactor;
  final int newInterval;
  final int newRepetitions;
  final String nextReviewDate;
  final int familiarityLevel;

  ReviewResult({
    required this.newEasinessFactor,
    required this.newInterval,
    required this.newRepetitions,
    required this.nextReviewDate,
    required this.familiarityLevel,
  });
}

class SRSService {
  /// Calculate familiarity level from Easiness Factor
  static int efToFamiliarityLevel(double ef) {
    if (ef < 1.7) return 1; // Unknown
    if (ef < 2.0) return 2; // Seen
    if (ef < 2.3) return 3; // Learning
    if (ef < 2.6) return 4; // Familiar
    return 5; // Mastered
  }

  /// Calculate new Easiness Factor based on quality of response
  static double calculateNewEF(double currentEF, int quality) {
    // Formula: EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    final newEF = currentEF + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    return newEF < 1.3 ? 1.3 : newEF;
  }

  /// Process a review and calculate new SRS data
  static ReviewResult processReview(SRSData currentData, int quality) {
    // Clamp quality to 0-5
    int q = quality;
    if (q < 0) q = 0;
    if (q > 5) q = 5;

    double newEF = currentData.easinessFactor;
    int newInterval = 0;
    int newRepetitions = 0;

    if (q < 3) {
      // Failed recall - reset repetitions, EF slightly decreases or stays same
      newRepetitions = 0;
      newInterval = 1; // Review tomorrow
      newEF = (currentData.easinessFactor - 0.2 < 1.3) ? 1.3 : currentData.easinessFactor - 0.2;
    } else {
      // Successful recall
      newEF = calculateNewEF(currentData.easinessFactor, q);
      newRepetitions = currentData.repetitions + 1;

      // Calculate new interval
      if (newRepetitions == 1) {
        newInterval = 1;
      } else if (newRepetitions == 2) {
        newInterval = 6;
      } else {
        newInterval = (currentData.interval * newEF).ceil();
      }
    }

    // Calculate next review date
    final now = DateTime.now();
    final nextReview = now.add(Duration(days: newInterval));
    
    return ReviewResult(
      newEasinessFactor: newEF,
      newInterval: newInterval,
      newRepetitions: newRepetitions,
      nextReviewDate: nextReview.toIso8601String(),
      familiarityLevel: efToFamiliarityLevel(newEF),
    );
  }
}
