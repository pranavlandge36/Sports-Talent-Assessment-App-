import 'dart:math';

class VerticalJumpCounter {
  double? _baselineHipY;
  double _maxDelta = 0.0;
  bool _inAir = false;

  DateTime _lastJumpTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ REALISTIC CAMERA-BASED THRESHOLDS (MoveNet normalized Y)
  static const double takeoffThreshold = 0.035; // upward motion
  static const double landingThreshold = 0.015; // near baseline
  static const int minJumpGapMs = 800;

  /// Estimated max jump height in cm
  /// Scaling factor tuned for phone side-view (~2–3m distance)
  int get maxJumpCm => (_maxDelta * 300).round();

  void reset() {
    _baselineHipY = null;
    _maxDelta = 0.0;
    _inAir = false;
    _lastJumpTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ SINGLE PARAMETER — MoveNet keypoints map
  void update(Map<String, Point<double>> kps) {
    // ✅ USE WHICHEVER HIP IS VISIBLE
    final hip = kps['left_hip'] ?? kps['right_hip'];
    if (hip == null) return;

    _baselineHipY ??= hip.y;

    final now = DateTime.now();
    final canJump = now.difference(_lastJumpTime).inMilliseconds > minJumpGapMs;

    // Positive delta = moving UP
    final delta = _baselineHipY! - hip.y;

    // 🔼 Takeoff
    if (!_inAir && delta > takeoffThreshold && canJump) {
      _inAir = true;
      _maxDelta = 0.0;
    }

    // ⛰ Track peak height
    if (_inAir && delta > _maxDelta) {
      _maxDelta = delta;
    }

    // 🔽 Landing
    if (_inAir && delta < landingThreshold) {
      _inAir = false;
      _baselineHipY = hip.y;
      _lastJumpTime = now;
    }

    // 🔍 DEBUG (remove later)
    print(
      'delta=${delta.toStringAsFixed(3)}  '
      'max=${_maxDelta.toStringAsFixed(3)}  '
      'cm=$maxJumpCm',
    );
  }
}
