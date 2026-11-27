import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui';

import 'package:mediapipe_vision/mediapipe_vision.dart';

const jointIndices = {
  'head': 0,
  'ls': 11,
  'rs': 12,
  'le': 13,
  're': 14,
  'lw': 15,
  'rw': 16,
  'lh': 23,
  'rh': 24,
  'lk': 25,
  'rk': 26,
  'la': 27,
  'ra': 28,
};
typedef Rig = Map<String, Offset>;
const bones = [
  ('head', 'ls'),
  ('head', 'rs'),
  ('ls', 'le'),
  ('le', 'lw'),
  ('rs', 're'),
  ('re', 'rw'),
  ('ls', 'lh'),
  ('rs', 'rh'),
  ('lh', 'lk'),
  ('lk', 'la'),
  ('rh', 'rk'),
  ('rk', 'ra'),
];

Rig visibleRig(List<NormalizedLandmark> landmarks) => {
  for (final entry in jointIndices.entries)
    if ((landmarks[entry.value].visibility ?? 1) >= .5 &&
        (landmarks[entry.value].presence ?? 1) >= .5)
      entry.key: Offset(landmarks[entry.value].x, landmarks[entry.value].y),
};

Rig decodeRig(Map<String, dynamic> data) => data.map(
  (k, v) =>
      MapEntry(k, Offset((v[0] as num).toDouble(), (v[1] as num).toDouble())),
);
Map<String, List<double>> encodeRig(Rig data) =>
    data.map((k, v) => MapEntry(k, [v.dx, v.dy]));

class ExtractedPose {
  ExtractedPose(this.svg, this.rig, this.aspect);
  final String svg;
  final Rig rig;
  final double aspect;
}

Future<ExtractedPose> extractPose(String path) async {
  final model = await PoseLandmarker.create(
    PoseLandmarkerOptions(
      model: VisionModels.poseLandmarker,
      numPoses: 2,
      outputSegmentationMasks: true,
    ),
  );
  try {
    final result = await model.detect(VisionImage.fromFile(path));
    if (result.poseLandmarks.isEmpty) {
      throw const FormatException('没有识别到人物，请换一张主体清晰的照片');
    }
    if (result.poseLandmarks.length != 1) {
      throw const FormatException('请选择一张单人参考照片');
    }
    final points = visibleRig(result.poseLandmarks.single);
    if (points.length < 7) throw const FormatException('可见关节太少，请换一张遮挡较少的照片');
    final mask = result.segmentationMasks?.firstOrNull;
    if (mask == null) throw const FormatException('没有提取到轮廓，请换一张照片');
    final step = math.max(1, (math.max(mask.width, mask.height) / 180).ceil());
    final rows = StringBuffer();
    int left = mask.width, top = mask.height, right = 0, bottom = 0;
    for (int y = 0; y < mask.height; y += step) {
      int? start;
      for (int x = 0; x < mask.width + step; x += step) {
        if (x < mask.width && mask.confidence[y * mask.width + x] >= .55) {
          start ??= x;
        } else if (start != null) {
          final end = math.min(x, mask.width),
              base = math.min(y + step, mask.height);
          rows.write('M$start $y H$end V$base H${start}Z');
          left = math.min(left, start);
          right = math.max(right, end);
          top = math.min(top, y);
          bottom = math.max(bottom, base);
          start = null;
        }
      }
    }
    if (right <= left || bottom <= top) {
      throw const FormatException('未找到清晰的人物轮廓');
    }
    final w = right - left, h = bottom - top;
    final aspect =
        w /
        h *
        (result.imageWidth / result.imageHeight) /
        (mask.width / mask.height);
    final rig = points.map(
      (k, v) => MapEntry(
        k,
        Offset((v.dx * mask.width - left) / w, (v.dy * mask.height - top) / h),
      ),
    );
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="${aspect * 300}" height="300" viewBox="$left $top $w $h" preserveAspectRatio="none"><path fill="#efe9df" d="$rows"/></svg>';
    return ExtractedPose(svg, rig, aspect);
  } finally {
    await model.dispose();
  }
}

String compareRig(
  Rig reference,
  Rig actual,
  double referenceAspect,
  double cameraAspect, {
  bool flip = false,
  double angle = 0,
}) {
  double sum = 0, worst = 0;
  int count = 0;
  String hint = '保持当前动作';
  for (final (a, b) in bones) {
    String source(String joint) {
      if (!flip || joint == 'head') return joint;
      return '${joint.startsWith('l') ? 'r' : 'l'}${joint.substring(1)}';
    }

    final from = reference[source(a)], to = reference[source(b)];
    final observedFrom = actual[a], observedTo = actual[b];
    if (from == null ||
        to == null ||
        observedFrom == null ||
        observedTo == null) {
      continue;
    }
    final ref = to - from, obs = observedTo - observedFrom;
    final x = ref.dx * referenceAspect * (flip ? -1 : 1);
    final target = Offset(
      x * math.cos(angle) - ref.dy * math.sin(angle),
      x * math.sin(angle) + ref.dy * math.cos(angle),
    );
    final measured = Offset(obs.dx * cameraAspect, obs.dy);
    if (target.distance < .015 || measured.distance < .015) continue;
    final delta = (target / target.distance) - (measured / measured.distance);
    final diff = delta.distance / 2;
    sum += diff;
    count++;
    if (diff > worst && diff > .20) {
      worst = diff;
      final part = const {
        'lw': '左手',
        'rw': '右手',
        'le': '左肘',
        're': '右肘',
        'lk': '左膝',
        'rk': '右膝',
        'la': '左脚',
        'ra': '右脚',
      }[b];
      hint = part == null
          ? '调整上身倾斜方向'
          : delta.dy.abs() >= delta.dx.abs()
          ? (delta.dy < 0 ? '抬高$part' : '放低$part')
          : '调整$part的横向位置';
    }
  }
  return count < 5
      ? '请让更多关节进入画面'
      : '动作匹配 ${((1 - sum / count) * 100).round()}% · $hint';
}

String matchPeople(
  List<Rig> targets,
  List<Rig> observed,
  double aspect,
  double cameraAspect, {
  required bool mirror,
  required bool previewMirror,
  required double angle,
}) {
  String compare(Rig target, Rig person) => compareRig(
    target,
    person,
    aspect,
    cameraAspect,
    flip: mirror ^ previewMirror,
    angle: previewMirror ? -angle : angle,
  );
  if (targets.length == 1) {
    return observed.isEmpty
        ? '请让身体进入画面'
        : compare(targets.single, observed.first);
  }
  if (observed.length < 2) return '已识别 ${observed.length}/2 人 · 请两人同时入镜';
  Offset? center(Rig r) {
    final pts = [
      'lh',
      'rh',
      'ls',
      'rs',
    ].map((k) => r[k]).whereType<Offset>().toList();
    return pts.length < 2
        ? null
        : pts.reduce((a, b) => a + b) / pts.length.toDouble();
  }

  final a = center(observed[0]), b = center(observed[1]);
  if (a == null || b == null || (a.dx - b.dx).abs() < .06) {
    return '请两人稍微分开，让肩膀和腰部可见';
  }
  double targetX(Rig r) {
    final p = center(r)! - const Offset(.5, .5);
    return p.dx * aspect * (mirror ? -1 : 1) * math.cos(angle) -
        p.dy * math.sin(angle);
  }

  final leftTarget = targetX(targets[0]) < targetX(targets[1]) ? 0 : 1;
  final leftPerson = ((a.dx < b.dx) ^ previewMirror) ? 0 : 1;
  String side(String label, int t, int p) =>
      '$label · ${compare(targets[t], observed[p]).replaceFirst('动作匹配 ', '')}';
  return [
    side('左位', leftTarget, leftPerson),
    side('右位', 1 - leftTarget, 1 - leftPerson),
  ].join('\n');
}

/// Tries each side of the frame when the full-frame pass misses a partner.
/// Coordinates from each crop are mapped back into the shared camera frame.
Future<List<Rig>> recoverPartners(
  VisionImage image,
  List<Rig> found,
  PoseLandmarker detector,
) async {
  final width = image.width!, height = image.height!, bytes = image.pixels!;
  final people = [...found];
  double? torso(Rig rig) {
    final points = [
      'ls',
      'rs',
      'lh',
      'rh',
    ].map((k) => rig[k]?.dx).whereType<double>().toList();
    return points.length < 2
        ? null
        : points.reduce((a, b) => a + b) / points.length;
  }

  for (final left in [true, false]) {
    final centers = people.map(torso).whereType<double>();
    if (centers.any((x) => left ? x < .47 : x > .53)) continue;
    final start = left ? 0 : (width * .46).floor(),
        end = left ? (width * .54).ceil() : width;
    final size = end - start, pixels = Uint8List(size * height * 3);
    for (int y = 0; y < height; y++) {
      pixels.setRange(
        y * size * 3,
        (y + 1) * size * 3,
        bytes,
        (y * width + start) * 3,
      );
    }
    final result = await detector.detect(
      VisionImage.fromPixels(
        pixels: pixels,
        width: size,
        height: height,
        format: VisionPixelFormat.rgb,
      ),
    );
    if (result.poseLandmarks.isEmpty) continue;
    final rig = visibleRig(
      result.poseLandmarks.first,
    ).map((k, v) => MapEntry(k, Offset((start + v.dx * size) / width, v.dy)));
    final x = torso(rig);
    if (x == null ||
        (left ? x > .52 : x < .48) ||
        centers.any((other) => (other - x).abs() < .13)) {
      continue;
    }
    people.add(rig);
    if (people.length >= 2) break;
  }
  return people;
}
