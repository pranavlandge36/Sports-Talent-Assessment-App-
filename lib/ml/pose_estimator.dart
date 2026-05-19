import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class PoseEstimator {
  late Interpreter _interpreter;
  bool _loaded = false;
  bool _busy = false;

  static const int inputSize = 192;

  // --------------------
  // Load MoveNet model
  // --------------------
  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/models/movenet_lightning.tflite',
      options: InterpreterOptions()..threads = 4,
    );
    _loaded = true;
    debugPrint('✅ MoveNet loaded');
    print(_interpreter.getOutputTensor(0).shape);
  }

  // --------------------
  // Run pose estimation
  // --------------------
  Future<Map<String, Point<double>>?> process(CameraImage image) async {
    if (!_loaded || _busy) return null;
    _busy = true;

    try {
      debugPrint('PoseEstimator.process() CALLED');

      final input = _preprocess(image);

      final output = List.generate(
        1,
        (_) => List.generate(
          1,
          (_) => List.generate(17, (_) => List.filled(3, 0.0)),
        ),
      );

      _interpreter.run(input, output);

      return _parseKeypoints(output);
    } catch (e) {
      debugPrint('❌ PoseEstimator error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  // --------------------
  // Image preprocessing
  // --------------------
  List<List<List<List<int>>>> _preprocess(CameraImage image) {
    final img.Image rgb = _convertYUV420(image);
    final img.Image resized = img.copyResize(
      rgb,
      width: inputSize,
      height: inputSize,
    );

    return [
      List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            pixel.r.toInt(),
            pixel.g.toInt(),
            pixel.b.toInt(),
          ]; // ❗ INT, NOT FLOAT
        }),
      ),
    ];
  }

  // --------------------
  // YUV420 → RGB
  // --------------------
  img.Image _convertYUV420(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final img.Image imgRGB = img.Image(width: width, height: height);

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yp = planeY.bytes[y * planeY.bytesPerRow + x];
        final int uvIndex = (y ~/ 2) * planeU.bytesPerRow + (x ~/ 2);

        final int up = planeU.bytes[uvIndex];
        final int vp = planeV.bytes[uvIndex];

        int r = (yp + 1.402 * (vp - 128)).round();
        int g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).round();
        int b = (yp + 1.772 * (up - 128)).round();

        imgRGB.setPixelRgb(
          x,
          y,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }
    }
    return imgRGB;
  }

  // --------------------
  // Parse MoveNet output
  // --------------------
  Map<String, Point<double>> _parseKeypoints(
    List<List<List<List<double>>>> output,
  ) {
    const names = [
      'nose',
      'left_eye',
      'right_eye',
      'left_ear',
      'right_ear',
      'left_shoulder',
      'right_shoulder',
      'left_elbow',
      'right_elbow',
      'left_wrist',
      'right_wrist',
      'left_hip',
      'right_hip',
      'left_knee',
      'right_knee',
      'left_ankle',
      'right_ankle',
    ];

    final Map<String, Point<double>> points = {};

    for (int i = 0; i < 17; i++) {
      final double y = output[0][0][i][0];
      final double x = output[0][0][i][1];
      final double confidence = output[0][0][i][2];

      // 🔴 CONFIDENCE FILTER (CRITICAL)
      if (confidence > 0.2) {
        points[names[i]] = Point(x, y);
      }
    }

    debugPrint('Detected joints: ${points.keys}');
    return points;
  }
}
