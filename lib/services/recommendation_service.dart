import 'scoring_service.dart';

class RecommendationService {
  final ScoringService _scoringService = ScoringService();

  /// ================= PERFORMANCE WEIGHTS =================
  final Map<String, Map<String, double>> sportWeights = {
    "Football": {
      "speed": 0.30,
      "endurance": 0.25,
      "agility": 0.20,
      "strength": 0.15,
      "jump": 0.10,
    },
    "Athletics": {
      "speed": 0.35,
      "endurance": 0.30,
      "jump": 0.15,
      "agility": 0.10,
      "strength": 0.10,
    },
    "Basketball": {
      "jump": 0.30,
      "agility": 0.25,
      "speed": 0.20,
      "strength": 0.15,
      "endurance": 0.10,
    },
    "Kabaddi": {
      "strength": 0.30,
      "agility": 0.25,
      "endurance": 0.20,
      "speed": 0.15,
      "jump": 0.10,
    },
  };

  /// ================= BODY SUITABILITY SCORING =================
  /// Returns score out of 100
  double _bodySuitability({
    required String sport,
    required double height,
    required double weight,
    required double chest,
  }) {
    double score = 0;

    switch (sport) {
      case "Football":
        if (height >= 170 && height <= 190) score += 40;
        if (weight >= 60 && weight <= 85) score += 30;
        if (chest >= 85 && chest <= 105) score += 30;
        break;

      case "Athletics":
        if (height >= 165 && height <= 185) score += 40;
        if (weight >= 55 && weight <= 75) score += 30;
        if (chest >= 80 && chest <= 95) score += 30;
        break;

      case "Basketball":
        if (height >= 180) score += 50;
        if (weight >= 65 && weight <= 95) score += 25;
        if (chest >= 90) score += 25;
        break;

      case "Kabaddi":
        if (height >= 165 && height <= 180) score += 30;
        if (weight >= 70 && weight <= 95) score += 40;
        if (chest >= 95) score += 30;
        break;
    }

    return score; // 0 - 100
  }

  /// ================= MAIN RECOMMENDATION FUNCTION =================
  Map<String, dynamic> recommendSport({
    required Map<String, double> percentiles,
    required double height,
    required double weight,
    required double chest,
  }) {
    Map<String, double> sportScores = {};

    sportWeights.forEach((sport, weights) {
      /// 1️⃣ Performance score (0–100)
      double performanceScore = _scoringService.calculateFinalScore(
        percentiles: percentiles,
        weights: weights,
      );

      /// 2️⃣ Body suitability score (0–100)
      double bodyScore = _bodySuitability(
        sport: sport,
        height: height,
        weight: weight,
        chest: chest,
      );

      /// 3️⃣ Combine scores
      /// 80% performance + 20% body profile
      double finalScore = (performanceScore * 0.8) + (bodyScore * 0.2);

      sportScores[sport] = finalScore;
    });

    /// Find best sport
    String bestSport = sportScores.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    double bestScore = sportScores[bestSport]!;

    String category = _scoringService.categorize(bestScore);

    return {
      "bestSport": bestSport,
      "score": bestScore,
      "category": category,
      "allScores": sportScores,
    };
  }
}
