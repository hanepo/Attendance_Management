import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class FaceService {
  static final FaceService _instance = FaceService._internal();
  factory FaceService() => _instance;
  FaceService._internal();

  FaceDetector? _detector;
  tfl.Interpreter? _interpreter;
  bool _initialized = false;

  static const double threshold = 1.0;

  Future<void> init() async {
    if (_initialized) return;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: false,
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    await _loadModel();
    _initialized = true;
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset('mobilefacenet.tflite');
    } catch (_) {
      _interpreter = null;
    }
  }

  /// Correct image format per platform.
  /// iOS outputs bgra8888, Android outputs nv21.
  static ImageFormatGroup get cameraImageFormat =>
      Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420;

  /// Build InputImage from CameraImage live stream for ML Kit.
  Future<List<Face>> detectFromCameraImage(
      CameraImage image, InputImageRotation rotation) async {
    _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    final InputImage? inputImage = _buildInputImage(image, rotation);
    if (inputImage == null) return [];
    try {
      return await _detector!.processImage(inputImage);
    } catch (_) {
      return [];
    }
  }

  InputImage? _buildInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      if (Platform.isIOS) {
        // iOS: single-plane BGRA8888
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      } else {
        // Android: multi-plane NV21
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        return InputImage.fromBytes(
          bytes: allBytes.done().buffer.asUint8List(),
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
    } catch (_) {
      return null;
    }
  }

  /// Convert CameraImage to imglib.Image for TFLite processing.
  imglib.Image? convertCameraImage(
      CameraImage image, CameraLensDirection direction) {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888(image, direction);
      } else if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(image, direction);
      }
    } catch (_) {}
    return null;
  }

  imglib.Image _convertBGRA8888(
      CameraImage image, CameraLensDirection direction) {
    final img = imglib.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: imglib.ChannelOrder.bgra,
    );
    // iOS front camera: rotate -90 to get upright portrait
    return direction == CameraLensDirection.front
        ? imglib.copyRotate(img, angle: -90)
        : imglib.copyRotate(img, angle: 90);
  }

  imglib.Image _convertYUV420(
      CameraImage image, CameraLensDirection direction) {
    final int width = image.width;
    final int height = image.height;
    final img = imglib.Image(width: width, height: height);
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int uvIndex =
            uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final int index = y * width + x;
        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        img.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return direction == CameraLensDirection.front
        ? imglib.copyRotate(img, angle: -90)
        : imglib.copyRotate(img, angle: 90);
  }

  /// Get face embedding directly from a raw CameraImage frame + already-detected face.
  /// Crops from the raw buffer (no full-image rotation), then rotates just the crop.
  List<double>? getFaceEmbeddingFromRawFrame(
      CameraImage image, Face face) {
    if (_interpreter == null) return null;
    try {
      imglib.Image rawImg;
      if (image.format.group == ImageFormatGroup.bgra8888) {
        rawImg = imglib.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
      } else {
        rawImg = _yuv420ToRaw(image);
      }

      final x = (face.boundingBox.left - 10).clamp(0.0, rawImg.width - 1.0);
      final y = (face.boundingBox.top - 10).clamp(0.0, rawImg.height - 1.0);
      final w = (face.boundingBox.width + 20).clamp(1.0, rawImg.width - x);
      final h = (face.boundingBox.height + 20).clamp(1.0, rawImg.height - y);

      imglib.Image cropped = imglib.copyCrop(
        rawImg,
        x: x.round(),
        y: y.round(),
        width: w.round(),
        height: h.round(),
      );

      // Rotate the small crop upright (iOS sensor is landscape-oriented)
      if (Platform.isIOS) {
        cropped = imglib.copyRotate(cropped, angle: -90);
      }

      cropped = imglib.copyResizeCropSquare(cropped, size: 112);

      final flat = _imageToFloat32(cropped, 112, 128, 128);
      final input = [
        List.generate(
          112,
          (i) => List.generate(112, (j) {
            final base = (i * 112 + j) * 3;
            return [flat[base], flat[base + 1], flat[base + 2]];
          }),
        ),
      ];
      final output = [List<double>.filled(192, 0.0)];
      _interpreter!.run(input, output);
      return output[0];
    } catch (_) {
      return null;
    }
  }

  /// YUV420 to imglib without rotation (for raw bounding-box cropping).
  imglib.Image _yuv420ToRaw(CameraImage image) {
    final int w = image.width;
    final int h = image.height;
    final img = imglib.Image(width: w, height: h);
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        final int uvIndex =
            uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final int index = y * w + x;
        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round().clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        img.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return img;
  }

  Float32List _imageToFloat32(
      imglib.Image image, int inputSize, double mean, double std) {
    final converted = Float32List(inputSize * inputSize * 3);
    int idx = 0;
    for (int i = 0; i < inputSize; i++) {
      for (int j = 0; j < inputSize; j++) {
        final pixel = image.getPixel(j, i);
        converted[idx++] = (pixel.r - mean) / std;
        converted[idx++] = (pixel.g - mean) / std;
        converted[idx++] = (pixel.b - mean) / std;
      }
    }
    return converted;
  }

  double euclideanDistance(List<double> e1, List<double> e2) {
    double sum = 0.0;
    for (int i = 0; i < e1.length; i++) {
      sum += pow(e1[i] - e2[i], 2);
    }
    return sqrt(sum);
  }

  bool isMatch(List<double> stored, List<double> current) =>
      euclideanDistance(stored, current) <= threshold;

  String embeddingToJson(List<double> embedding) => jsonEncode(embedding);

  List<double>? jsonToEmbedding(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _detector?.close();
    _interpreter?.close();
    _initialized = false;
    _detector = null;
    _interpreter = null;
  }
}
