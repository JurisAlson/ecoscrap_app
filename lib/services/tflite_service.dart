// lib/services/tflite_service.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  static const String _modelAssetPath = 'assets/models/plastic_model.tflite';
  static const int _inputSize = 224;

  static bool _isRunning = false;

  static Future<double> runModel(String imagePath) async {
    if (_isRunning) {
      throw Exception('Model is already running.');
    }

    _isRunning = true;
    Interpreter? interpreter;

    try {
      debugPrint('TFLite: creating interpreter');

      final options = InterpreterOptions()
        ..threads = 1;

      interpreter = await Interpreter.fromAsset(
        _modelAssetPath,
        options: options,
      );

      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);

      debugPrint(
        'TFLite: input shape=${inputTensor.shape}, type=${inputTensor.type}',
      );
      debugPrint(
        'TFLite: output shape=${outputTensor.shape}, type=${outputTensor.type}',
      );

      _validateModelShape(inputTensor.shape, outputTensor.shape);

      debugPrint('TFLite: preprocess start');
      final Float32List input = _preprocessSingleInput(imagePath);
      debugPrint('TFLite: preprocess done');

      final output = List.generate(1, (_) => List.filled(1, 0.0));

      debugPrint('TFLite: inference start');
      interpreter.run(
        input.reshape([1, _inputSize, _inputSize, 3]),
        output,
      );
      debugPrint('TFLite: inference done');

      final double raw = (output[0][0] as num).toDouble();
      final double p = raw.clamp(0.0, 1.0);

      debugPrint('TFLite: prediction=$p');
      return p;
    } catch (e, st) {
      debugPrint('TFLite: runModel failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    } finally {
      try {
        interpreter?.close();
        debugPrint('TFLite: interpreter closed');
      } catch (_) {}

      _isRunning = false;
    }
  }

  static void _validateModelShape(
    List<int> inputShape,
    List<int> outputShape,
  ) {
    final expectedInput = [1, _inputSize, _inputSize, 3];
    final expectedOutput0 = [1, 1];

    if (inputShape.length != 4 ||
        inputShape[0] != expectedInput[0] ||
        inputShape[1] != expectedInput[1] ||
        inputShape[2] != expectedInput[2] ||
        inputShape[3] != expectedInput[3]) {
      throw Exception(
        'Unexpected model input shape: $inputShape. '
        'Expected: $expectedInput',
      );
    }

    if (outputShape.length != 2 ||
        outputShape[0] != expectedOutput0[0] ||
        outputShape[1] != expectedOutput0[1]) {
      throw Exception(
        'Unexpected model output shape: $outputShape. '
        'Expected something like: $expectedOutput0',
      );
    }
  }
}

Float32List _preprocessSingleInput(String imagePath) {
  final file = File(imagePath);

  if (!file.existsSync()) {
    throw Exception('Image file does not exist: $imagePath');
  }

  final bytes = file.readAsBytesSync();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('Could not decode image.');
  }

  debugPrint(
    'TFLite: original image size=${decoded.width}x${decoded.height}',
  );

  final cropped = _centerSquareCrop(decoded);

  debugPrint(
    'TFLite: cropped image size=${cropped.width}x${cropped.height}',
  );

  return _toInputBuffer(cropped);
}

img.Image _centerSquareCrop(img.Image image) {
  final int s = image.width < image.height ? image.width : image.height;
  final int x = (image.width - s) ~/ 2;
  final int y = (image.height - s) ~/ 2;

  return img.copyCrop(
    image,
    x: x,
    y: y,
    width: s,
    height: s,
  );
}

Float32List _toInputBuffer(img.Image image) {
  final resized = img.copyResize(
    image,
    width: TFLiteService._inputSize,
    height: TFLiteService._inputSize,
    interpolation: img.Interpolation.average,
  );

  final buffer = Float32List(
    TFLiteService._inputSize * TFLiteService._inputSize * 3,
  );

  int index = 0;

  for (int y = 0; y < TFLiteService._inputSize; y++) {
    for (int x = 0; x < TFLiteService._inputSize; x++) {
      final pixel = resized.getPixel(x, y);

      buffer[index++] = (pixel.r / 127.5) - 1.0;
      buffer[index++] = (pixel.g / 127.5) - 1.0;
      buffer[index++] = (pixel.b / 127.5) - 1.0;
    }
  }

  return buffer;
}