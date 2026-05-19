class ScoringService {
  double calculateFinalScore({
    required Map<String, double> percentiles,
    required Map<String, double> weights,
  }) {
    double total = 0;

    weights.forEach((key, weight) {
      if (percentiles.containsKey(key)) {
        total += percentiles[key]! * weight;
      }
    });

    return total;
  }

  String categorize(double score) {
    if (score >= 90) return "Elite";
    if (score >= 80) return "State Level Potential";
    if (score >= 70) return "District Level";
    if (score >= 60) return "School Competitive";
    return "Development Required";
  }
}
