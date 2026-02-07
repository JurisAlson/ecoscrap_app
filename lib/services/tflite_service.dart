  import 'dart:io';
  import 'package:tflite_flutter/tflite_flutter.dart';
  import 'package:image/image.dart' as img;

  /// Service that caches interpreter
  class TFLiteService {
    static Interpreter? _interpreter;

    static Future<void> init() async {
      if (_interpreter != null) return;

      _interpreter = await Interpreter.fromAsset(
        'assets/models/plastic_model.tflite',
        options: InterpreterOptions()..threads = 2,
      );
    final in0 = _interpreter!.getInputTensor(0);
    final out0 = _interpreter!.getOutputTensor(0);
    print('Input shape: ${in0.shape}, type: ${in0.type}');
    print('Output shape: ${out0.shape}, type: ${out0.type}');
    }

    static Future<double> runModel(String imagePath) async {
      await init();
      final interpreter = _interpreter!;

      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes)!;

      const inputSize = 224;
      final resized = img.copyResize(image, width: inputSize, height: inputSize);

      final input = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (_) => List.generate(
            inputSize,
            (_) => List.filled(3, 0.0),
          ),
        ),
      );

      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final p = resized.getPixel(x, y);
          input[0][y][x][0] = p.r / 255.0;
          input[0][y][x][1] = p.g / 255.0;
          input[0][y][x][2] = p.b / 255.0;
        }
      }

      final output = List.generate(1, (_) => List.filled(1, 0.0)); // [1,1]
      interpreter.run(input, output);

      return output[0][0];
    }

  }
