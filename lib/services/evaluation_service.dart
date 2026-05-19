import 'firebase_service.dart';
import 'percentile_service.dart';
import 'recommendation_service.dart';

class EvaluationService {
  final FirebaseService _firebaseService = FirebaseService();
  final PercentileService _percentileService = PercentileService();
  final RecommendationService _recommendationService = RecommendationService();

  // Map activityKey → performance metric
  String mapActivityToMetric(String activityKey) {
    switch (activityKey) {
      case "pushups":
        return "strength";
      case "endurance_run":
        return "endurance";
      case "sprint_30m":
        return "speed";
      case "shuttle_run":
        return "agility";
      case "vertical_jump":
        return "jump";
      default:
        return "";
    }
  }

  Future<Map<String, dynamic>?> evaluateAthlete({
    required String userId,
    required int age,
    required String gender,
    required double height,
    required double weight,
    required double chest,
  }) async {
    /// 1️⃣ Fetch best scores
    Map<String, dynamic> rawScores = await _firebaseService.fetchBestScores(
      userId,
    );

    if (rawScores.isEmpty) return null;

    /// 2️⃣ Fetch normative data
    var normativeData = await _firebaseService.fetchNormativeData(age, gender);

    if (normativeData == null) return null;

    Map<String, double> percentiles = {};

    /// 3️⃣ Convert raw scores → percentiles
    rawScores.forEach((activityKey, score) {
      String metric = mapActivityToMetric(activityKey);

      if (metric.isEmpty) return;

      if (!normativeData.containsKey(activityKey)) return;

      final activityNorm = normativeData[activityKey];

      double mean = (activityNorm['mean'] as num).toDouble();
      double std = (activityNorm['std'] as num).toDouble();

      bool lowerIsBetter =
          activityKey.contains("run") || activityKey.contains("sprint");

      double percentile = _percentileService.calculatePercentile(
        score: (score as num).toDouble(),
        mean: mean,
        std: std,
        lowerIsBetter: lowerIsBetter,
      );

      percentiles[metric] = percentile;
    });

    if (percentiles.isEmpty) return null;

    /// 4️⃣ Get recommendation (now includes body metrics)
    var recommendation = _recommendationService.recommendSport(
      percentiles: percentiles,
      height: height,
      weight: weight,
      chest: chest,
    );

    return {"percentiles": percentiles, "recommendation": recommendation};
  }
}
