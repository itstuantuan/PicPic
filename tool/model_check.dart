import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraImage;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:picpic/features/live_guide.dart';

import 'package:flutter/services.dart';
import 'package:picpic/features/pose_vision.dart';
import 'package:picpic/features/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真人样张产生 33 个关节及前景轮廓', () async {
    final cache = await Directory.systemTemp.createTemp('picpic-model');
    addTearDown(() => cache.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => cache.path,
        );
    final file = Platform.environment['PICPIC_POSE_SAMPLE']!;
    final extracted = await extractPose(file);
    expect(extracted.rig.length, greaterThanOrEqualTo(7));
    expect(extracted.svg, contains('<path'));
    expect(extracted.aspect, greaterThan(0));
    final video = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        model: VisionModels.poseLandmarker,
        runningMode: RunningMode.video,
      ),
    );
    try {
      final codec = await ui.instantiateImageCodec(
        await File(file).readAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      final bits = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      for (int i = 0; i < bits.length; i += 4) {
        final red = bits[i];
        bits[i] = bits[i + 2];
        bits[i + 2] = red;
      }
      final frame = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
          width: image.width,
          height: image.height,
          planes: [
            CameraImagePlane(
              bytes: bits,
              bytesPerRow: image.width * 4,
              bytesPerPixel: 4,
            ),
          ],
        ),
      );
      image.dispose();
      codec.dispose();
      for (final stamp in [0, 240]) {
        final result = await video.detectForVideo(
          frameForPose(frame, 0),
          timestampMilliseconds: stamp,
        );
        expect(result.poseLandmarks.single.length, 33);
      }
    } finally {
      await video.dispose();
    }
    final model = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        model: VisionModels.poseLandmarker,
        outputSegmentationMasks: true,
      ),
    );
    try {
      final result = await model.detect(VisionImage.fromFile(file));
      expect(result.poseLandmarks.single.length, 33);
      expect(
        result.segmentationMasks!.single.confidence.any((p) => p > .8),
        isTrue,
      );
      if (Platform.environment['PICPIC_EXPORT_RIGS'] == '1') {
        final rigs = <String, dynamic>{};
        for (final p in Pose.values.where((p) => p.asset.endsWith('.png'))) {
          final r = await model.detect(
            VisionImage.fromFile(File(p.asset).absolute.path),
          );
          if (r.poseLandmarks.isNotEmpty) {
            final rig = visibleRig(r.poseLandmarks.first);
            if (rig.length >= 7) rigs[p.id] = encodeRig(rig);
          }
        }
        await File('assets/studies/reference_rigs.json')
            .writeAsString(jsonEncode(rigs));
      }
    } finally {
      await model.dispose();
    }
  });
}
