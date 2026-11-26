import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

import 'pose_vision.dart';

/// Resamples directly into upright RGB so landmarks use the same axes as the preview.
VisionImage frameForPose(CameraImage image, int rotation) {
  final step = math.max(1, (math.max(image.width, image.height) / 480).ceil());
  final w = (image.width / step).ceil(), h = (image.height / step).ceil();
  final turn = rotation == 90 || rotation == 270;
  final width = turn ? h : w, height = turn ? w : h;
  final rgb = Uint8List(width * height * 3);
  final planes = image.planes;
  final bgra = image.format.group == ImageFormatGroup.bgra8888;
  if (!bgra &&
      (image.format.group != ImageFormatGroup.yuv420 || planes.length != 3)) {
    throw const FormatException('此设备的相机帧格式暂不支持');
  }
  int sample(Plane p, int x, int y) =>
      p.bytes[y * p.bytesPerRow + x * (p.bytesPerPixel ?? 1)];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final sx = x * step, sy = y * step;
      final (dx, dy) = switch (rotation) {
        90 => (h - 1 - y, x),
        180 => (w - 1 - x, h - 1 - y),
        270 => (y, w - 1 - x),
        _ => (x, y),
      };
      final dst = (dy * width + dx) * 3;
      if (bgra) {
        final src = sy * planes[0].bytesPerRow + sx * 4,
            bytes = planes[0].bytes;
        rgb[dst] = bytes[src + 2];
        rgb[dst + 1] = bytes[src + 1];
        rgb[dst + 2] = bytes[src];
      } else {
        final l = sample(planes[0], sx, sy) - 16,
            u = sample(planes[1], sx ~/ 2, sy ~/ 2) - 128,
            v = sample(planes[2], sx ~/ 2, sy ~/ 2) - 128;
        rgb[dst] = ((298 * l + 409 * v + 128) >> 8).clamp(0, 255);
        rgb[dst + 1] = ((298 * l - 100 * u - 208 * v + 128) >> 8).clamp(0, 255);
        rgb[dst + 2] = ((298 * l + 516 * u + 128) >> 8).clamp(0, 255);
      }
    }
  }
  return VisionImage.fromPixels(
    pixels: rgb,
    width: width,
    height: height,
    format: VisionPixelFormat.rgb,
  );
}

class LiveGuide extends StatefulWidget {
  const LiveGuide({
    super.key,
    required this.camera,
    required this.reference,
    required this.aspect,
    required this.flip,
    required this.angle,
  });
  final CameraController camera;
  final Rig reference;
  final double aspect, angle;
  final bool flip;
  @override
  State<LiveGuide> createState() => LiveGuideState();
}

class LiveGuideState extends State<LiveGuide> {
  String status = '开启动作匹配';
  bool active = false, busy = false, closed = false;
  int revision = 0;
  final clock = Stopwatch()..start();
  int last = -1000;
  PoseLandmarker? model;
  Future<void>? processing;
  Future<void> serial = Future.value();
  void toggle() {
    setState(() {
      active = !active;
      status = active ? '正在加载模型' : '开启动作匹配';
    });
    final id = ++revision;
    serial = serial.then((_) async {
      await release();
      if (closed || id != revision || !active) return;
      try {
        model = await PoseLandmarker.create(
          PoseLandmarkerOptions(
            model: VisionModels.poseLandmarker,
            runningMode: RunningMode.video,
          ),
        );
        if (closed || id != revision) {
          await release();
          return;
        }
        await controller.startImageStream((image) {
          if (closed ||
              id != revision ||
              busy ||
              clock.elapsedMilliseconds - last < 220) {
            return;
          }
          busy = true;
          last = clock.elapsedMilliseconds;
          processing = analyze(image, id).whenComplete(() => busy = false);
        });
        ownsStream = true;
      } catch (e) {
        fail(e, id);
      }
    });
  }

  late final CameraController controller;
  bool ownsStream = false;
  Future<void> suspend() {
    ++revision;
    active = false;
    if (mounted) setState(() => status = '开启动作匹配');
    serial = serial.then((_) => release());
    return serial;
  }

  Future<void> release() async {
    try {
      if (ownsStream &&
          controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    ownsStream = false;
    await processing;
    final old = model;
    model = null;
    await old?.dispose();
  }

  void fail(Object e, int id) {
    if (closed || id != revision) return;
    debugPrint('PicPic live guidance: $e');
    ++revision;
    setState(() {
      active = false;
      status = '识别不可用 · 点此重试';
    });
    serial = serial.then((_) => release());
  }

  Future<void> analyze(CameraImage frame, int id) async {
    try {
      final device = controller.description;
      final front = device.lensDirection == CameraLensDirection.front;
      final orientation = switch (controller.value.deviceOrientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final rotation = Platform.isIOS
          ? 0
          : (device.sensorOrientation +
                    (front ? orientation : -orientation) +
                    360) %
                360;
      final image = frameForPose(frame, rotation);
      final result = await model!.detectForVideo(
        image,
        timestampMilliseconds: last,
      );
      if (closed || id != revision) return;
      final rig = result.poseLandmarks.isEmpty
          ? <String, Offset>{}
          : visibleRig(result.poseLandmarks.first);
      final message = rig.isEmpty
          ? '请让身体进入画面'
          : compareRig(
              widget.reference,
              rig,
              widget.aspect,
              image.width! / image.height!,
              flip: widget.flip ^ (front && Platform.isAndroid),
              angle: (front && Platform.isAndroid)
                  ? -widget.angle
                  : widget.angle,
            );
      if (message != status) setState(() => status = message);
    } catch (e) {
      fail(e, id);
    }
  }

  @override
  void initState() {
    super.initState();
    controller = widget.camera;
  }

  @override
  void dispose() {
    closed = true;
    ++revision;
    serial = serial.then((_) => release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
    ),
    onPressed: toggle,
    icon: Icon(active ? Icons.accessibility_new : Icons.center_focus_strong),
    label: Text(status),
  );
}
