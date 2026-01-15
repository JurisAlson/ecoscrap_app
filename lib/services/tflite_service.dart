import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Service that caches interpreter
class TFLiteService {
  static Interpreter? _interpreter;

  static Future<Interpreter> getInterpreter() async {
    if (_interpreter != null) return _interpreter!;
    _interpreter = await Interpreter.fromAsset(
      'models/plastic_model.tflite',
      options: InterpreterOptions()..threads = 2,
    );
    return _interpreter!;
  }
}

/// Top-level function for compute
Future<List<double>> runModelInBackground(String imagePath) async {
  final interpreter = await TFLiteService.getInterpreter();

  // Load image bytes
  final file = File(imagePath);
  final bytes = await file.readAsBytes();
  final image = img.decodeImage(bytes)!;

  // Resize
  const inputSize = 224;
  final resized = img.copyResize(image, width: inputSize, height: inputSize);

  // Prepare input tensor
  final input = List.generate(1, (_) => List.generate(inputSize,
      (_) => List.generate(inputSize, (_) => List.filled(3, 0.0))));

  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel = resized.getPixel(x, y);
      input[0][y][x][0] = pixel.r / 255.0;
      input[0][y][x][1] = pixel.g / 255.0;
      input[0][y][x][2] = pixel.b / 255.0;
    }
  }

  // Prepare output tensor
  final output = List.generate(1, (_) => List.filled(2, 0.0));

  // Run inference
  interpreter.run(input, output);

  return output[0]; // [recyclableScore, nonRecyclableScore]
}
