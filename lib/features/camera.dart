import 'dart:io';

import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';

import '../shoot_session.dart';
import 'catalog.dart';
import 'live_guide.dart';

class Viewfinder extends StatefulWidget {
  const Viewfinder({
    super.key,
    required this.demo,
    this.initial = Pose.crouch,
    this.onUse,
    this.onSaved,
  });
  final Pose initial;
  final ValueChanged<Pose>? onUse;
  final Future<void> Function(Pose, String)? onSaved;
  final bool demo;
  @override
  State<Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<Viewfinder> {
  late Pose pose = widget.initial;
  bool preview = false;
  static const centered = Offset(.5, .5);
  Offset position = centered;
  double scale = 1;
  double startScale = 1;

  ShootSession? session;
  GlobalKey<LiveGuideState> guideKey = GlobalKey<LiveGuideState>();
  CameraController? guideCamera;
  String? photo;
  bool working = false, mirrored = false, saved = false, grid = false;
  double opacity = .56, angle = 0, startAngle = 0;
  int step = 0, countdown = 0;
  bool selfTimer = false, inGallery = false;
  @override
  void initState() {
    super.initState();
    if (!widget.demo) startCamera();
  }

  void startCamera() {
    session = ShootSession()..addListener(refresh);
  }

  void refresh() {
    if (guideCamera != session?.controller) {
      guideKey = GlobalKey<LiveGuideState>();
      guideCamera = session?.controller;
    }

    if (mounted) setState(() {});
  }

  void useDemo() {
    session?.removeListener(refresh);
    session?.dispose();
    setState(() => session = null);
  }

  @override
  void dispose() {
    session?.removeListener(refresh);
    session?.dispose();
    super.dispose();
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> toggleFlash() async {
    final camera = session?.controller;
    if (camera == null || working) return;
    setState(() => working = true);
    try {
      await camera.setFlashMode(
        camera.value.flashMode == FlashMode.always
            ? FlashMode.off
            : FlashMode.always,
      );
    } on CameraException {
      notice('当前镜头无法切换闪光灯');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> sharePhoto(BuildContext anchor) async {
    final path = photo;
    if (working || path == null) return;
    final box = anchor.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => working = true);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
      );
    } catch (_) {
      notice('未能打开系统分享，请重试');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> shoot() async {
    if (working) return;
    final camera = session?.controller;
    if (session != null && camera == null) return;
    setState(() => working = true);
    try {
      if (selfTimer) {
        for (int seconds = 3; seconds > 0; seconds--) {
          setState(() => countdown = seconds);
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted ||
              camera != session?.controller ||
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) {
            return;
          }
        }
      }
      await guideKey.currentState?.suspend();
      if (!mounted || camera != session?.controller) return;
      final file = await camera?.takePicture();
      if (mounted) {
        setState(() {
          photo = file?.path;
          preview = true;
          saved = false;
          inGallery = false;
        });
      }
    } catch (_) {
      notice('拍摄失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          countdown = 0;
        });
      }
    }
  }

  Future<void> save() async {
    if (working || saved || photo == null) return;
    setState(() => working = true);
    try {
      if (!inGallery) {
        await Gal.putImage(photo!);
        inGallery = true;
      }
      await widget.onSaved?.call(pose, photo!);
      if (mounted) setState(() => saved = true);
    } catch (_) {
      notice(inGallery ? '原片已存相册，更新拍摄记录失败，可重试' : '保存失败，请检查相册权限后重试');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget scene() {
    if (preview && photo != null) {
      return Image.file(File(photo!), fit: BoxFit.cover);
    }
    if (session == null) {
      return Image.asset('assets/street.jpg', fit: BoxFit.cover);
    }
    final camera = session!.controller;
    if (camera == null) return const ColoredBox(color: Color(0xff242321));
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final size = camera.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait ? size.height : size.width,
          height: portrait ? size.width : size.height,
          child: CameraPreview(camera),
        ),
      ),
    );
  }

  Future<void> choosePose() async {
    final result = await showModalBottomSheet<Pose>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择姿势', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              Flexible(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 155,
                    mainAxisExtent: 132,
                  ),
                  itemCount: Pose.values.length,
                  itemBuilder: (context, index) {
                    final p = Pose.values[index];
                    return TextButton(
                      onPressed: () => Navigator.pop(context, p),
                      child: Column(
                        children: [
                          Expanded(child: PoseImage(p, thumbnail: true)),
                          Text(
                            p.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      await guideKey.currentState?.suspend();
      if (!mounted) return;
      setState(() {
        widget.onUse?.call(result);
        pose = result;
        step = 0;
        angle = 0;
        mirrored = false;
        scale = 1;
        position = centered;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        scene(),
        if (grid && !preview)
          const IgnorePointer(child: CustomPaint(painter: GridLines())),
        if (!preview)
          LayoutBuilder(
            builder: (context, bounds) {
              final width = bounds.maxWidth;
              final height = bounds.maxHeight;
              final h = (height * pose.heightFraction * scale).clamp(
                1.0,
                height,
              );
              final w = (h * pose.aspectRatio).clamp(1.0, width);
              final dx = width - w, dy = height - h;
              return Stack(
                children: [
                  Positioned(
                    left: dx * position.dx,
                    top: dy * position.dy,
                    width: w,
                    height: h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) {
                        startScale = scale;
                        startAngle = angle;
                      },
                      onScaleUpdate: (d) => setState(() {
                        angle = startAngle + d.rotation;
                        scale = (startScale * d.scale).clamp(.55, 1.55);
                        position = Offset(
                          dx <= 0
                              ? .5
                              : (position.dx + d.focalPointDelta.dx / dx).clamp(
                                  0,
                                  1,
                                ),
                          dy <= 0
                              ? .5
                              : (position.dy + d.focalPointDelta.dy / dy).clamp(
                                  0,
                                  1,
                                ),
                        );
                      }),
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle: angle,
                          child: Transform.flip(
                            flipX: mirrored,
                            child: PoseImage(pose),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              tooltip: '返回',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          const Flexible(
                            child: Text(
                              'PicPic',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 6)],
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (!preview)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: '构图网格',
                                    onPressed: () =>
                                        setState(() => grid = !grid),
                                    icon: Icon(
                                      grid ? Icons.grid_on : Icons.grid_off,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '镜像人偶',
                                    onPressed: () =>
                                        setState(() => mirrored = !mirrored),
                                    icon: const Icon(Icons.flip),
                                  ),
                                  IconButton(
                                    tooltip: '人偶透明度',
                                    onPressed: () => setState(
                                      () => opacity = opacity == .56
                                          ? .32
                                          : opacity == .32
                                          ? .8
                                          : .56,
                                    ),
                                    icon: const Icon(Icons.opacity),
                                  ),
                                  if (session?.controller != null &&
                                      session!.cameras
                                              .map((c) => c.lensDirection)
                                              .toSet()
                                              .length >
                                          1)
                                    IconButton(
                                      tooltip: '切换镜头',
                                      onPressed: working ? null : session!.flip,
                                      icon: const Icon(
                                        Icons.cameraswitch_outlined,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (preview)
                        const Chip(label: Text('成片预览'))
                      else
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              setState(() => step = (step + 1) % 3),
                          icon: Text('${step + 1}/3'),
                          label: Text(pose.steps[step]),
                        ),
                      if (session?.controller case final camera?
                          when !preview && pose.supportsGuidance)
                        LiveGuide(
                          key: guideKey,
                          camera: camera,
                          references:
                              Pose.duoRigs[pose.id] ?? [Pose.rigs[pose.id]!],
                          aspect: pose.aspectRatio,
                          flip: mirrored,
                          angle: angle,
                        ),
                      if (!preview &&
                          session?.controller != null &&
                          !pose.supportsGuidance)
                        const Text(
                          '此姿势可手动对齐',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      if (!preview && session == null)
                        TextButton(
                          onPressed: () => setState(startCamera),
                          child: const Text(
                            '示例取景 · 打开相机',
                            style: TextStyle(
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 5)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (countdown > 0)
                Center(
                  child: Text(
                    '$countdown',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 8)],
                    ),
                  ),
                ),
              if (!preview && session != null && session!.controller == null)
                Center(
                  child: session!.error == null
                      ? const CircularProgressIndicator()
                      : Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(session!.error!),
                                TextButton(
                                  onPressed: session!.configure,
                                  child: const Text('重试'),
                                ),
                                TextButton(
                                  onPressed: useDemo,
                                  child: const Text('体验示例取景'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: preview
                      ? Wrap(
                          spacing: 12,
                          children: [
                            if (photo != null)
                              FilledButton(
                                onPressed: working || saved ? null : save,
                                child: Text(saved ? '已保存' : '保存到相册'),
                              ),
                            if (photo != null)
                              Builder(
                                builder: (anchor) => OutlinedButton(
                                  onPressed: working
                                      ? null
                                      : () => sharePhoto(anchor),
                                  child: const Text('分享原片'),
                                ),
                              ),
                            FilledButton.tonal(
                              onPressed: working
                                  ? null
                                  : () => setState(() => preview = false),
                              child: const Text('返回取景'),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity,
                          height: 72,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                left: 22,
                                child: IconButton.filledTonal(
                                  tooltip: selfTimer ? '关闭三秒自拍' : '三秒自拍',
                                  onPressed: working
                                      ? null
                                      : () => setState(
                                          () => selfTimer = !selfTimer,
                                        ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  icon: Icon(
                                    selfTimer
                                        ? Icons.timer_3
                                        : Icons.timer_outlined,
                                  ),
                                ),
                              ),
                              if (session?.controller case final camera?
                                  when camera.description.lensDirection ==
                                      CameraLensDirection.back)
                                Positioned(
                                  left: 66,
                                  child: IconButton(
                                    tooltip:
                                        camera.value.flashMode ==
                                            FlashMode.always
                                        ? '关闭闪光灯'
                                        : '开启闪光灯',
                                    onPressed: working ? null : toggleFlash,
                                    icon: Icon(switch (camera.value.flashMode) {
                                      FlashMode.off => Icons.flash_off,
                                      FlashMode.auto => Icons.flash_auto,
                                      _ => Icons.flash_on,
                                    }),
                                  ),
                                ),
                              Semantics(
                                button: true,
                                label: session == null ? '模拟拍照' : '拍照',
                                child: GestureDetector(
                                  onTap: working ? null : shoot,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 22,
                                child: IconButton.filledTonal(
                                  tooltip: '选择姿势',
                                  onPressed: working ? null : choosePose,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  icon: PoseImage(pose, height: 33, width: 33),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class GridLines extends CustomPainter {
  const GridLines();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * f, 0),
        Offset(size.width * f, size.height),
        pen,
      );
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(GridLines oldDelegate) => false;
}
