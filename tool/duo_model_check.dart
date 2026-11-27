import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:picpic/features/pose_vision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('原生模型识别真实双人照片中的两组独立人体关键点', () async {
    final cache = await Directory.systemTemp.createTemp('picpic-duo');
    addTearDown(() => cache.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => cache.path,
        );
    final model = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        model: VisionModels.poseLandmarker,
        numPoses: 2,
        runningMode: RunningMode.video,
      ),
    );
    try {
      final file = Platform.environment['PICPIC_DUO_SAMPLE']!;
      final codec = await ui.instantiateImageCodec(
        await File(file).readAsBytes(),
        targetWidth: 360,
      );
      final img = (await codec.getNextFrame()).image;
      final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final rgb = Uint8List(img.width * img.height * 3);
      for (int i = 0; i < img.width * img.height; i++) {
        rgb.setRange(i * 3, i * 3 + 3, rgba, i * 4);
      }
      final image = VisionImage.fromPixels(
        pixels: rgb,
        width: img.width,
        height: img.height,
        format: VisionPixelFormat.rgb,
      );
      img.dispose();
      codec.dispose();
      final r = await model.detectForVideo(image, timestampMilliseconds: 0);
      var rigs = r.poseLandmarks.map(visibleRig).toList();
      if (rigs.length < 2) {
        final secondary = await PoseLandmarker.create(
          PoseLandmarkerOptions(model: VisionModels.poseLandmarker),
        );
        try {
          rigs = await recoverPartners(image, rigs, secondary);
        } finally {
          await secondary.dispose();
        }
      }
      expect(rigs.length, 2);
      expect(
        rigs.every((r) => r.containsKey('ls') && r.containsKey('rs')),
        isTrue,
      );
    } finally {
      await model.dispose();
    }
  });
}
