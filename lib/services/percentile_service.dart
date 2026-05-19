import 'dart:math';

class PercentileService {
  // Normal CDF approximation
  double _normalCDF(double z) {
    return 0.5 * (1 + erf(z / sqrt(2)));
  }

  // Error function approximation
  double erf(double x) {
    // Abramowitz and Stegun approximation
    double t = 1.0 / (1.0 + 0.5 * x.abs());

    double tau =
        t *
        exp(
          -x * x -
              1.26551223 +
              t *
                  (1.00002368 +
                      t *
                          (0.37409196 +
                              t *
                                  (0.09678418 +
                                      t *
                                          (-0.18628806 +
                                              t *
                                                  (0.27886807 +
                                                      t *
                                                          (-1.13520398 +
                                                              t *
                                                                  (1.48851587 +
                                                                      t *
                                                                          (-0.82215223 +
                                                                              t * 0.17087277)))))))),
        );

    return x >= 0 ? 1 - tau : tau - 1;
  }

  /// Converts raw score to percentile
  /// If lowerIsBetter = true (like sprint time), inversion is applied
  double calculatePercentile({
    required double score,
    required double mean,
    required double std,
    bool lowerIsBetter = false,
  }) {
    if (std == 0) return 50;

    double z = lowerIsBetter ? (mean - score) / std : (score - mean) / std;

    double percentile = _normalCDF(z) * 100;

    return percentile.clamp(0, 100);
  }
}
