import 'dart:io';

import 'package:camera/camera.dart';
import 'package:gal/gal.dart';

import 'shoot_session.dart';

import 'package:flutter/material.dart';

void main() =>
    runApp(const PoseDemo(demo: bool.fromEnvironment('PICPIC_DEMO')));

class PoseDemo extends StatelessWidget {
  const PoseDemo({super.key, this.demo = false});
  final bool demo;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PicPic',
    theme: ThemeData.dark(useMaterial3: true),
    home: Viewfinder(demo: demo),
  );
}

enum Pose {
  crouch('蹲姿托腮', 'assets/crouch.png', 498 / 756, .43, [
    '手肘搭在膝盖上，轻轻托腮',
    '重心放低，让双膝自然分开',
    '侧过脸，视线朝向镜头',
  ]),
  stand('侧身扶头', 'assets/stand.png', 418 / 1012, .60, [
    '单手扶住后脑，另一只手轻搭腰间',
    '身体稍微侧向镜头',
    '放松肩膀，把重心移到一条腿上',
  ]),
  lookBack('回眸', 'assets/poses/01-回眸.png', 806 / 1952, .60, [
    '背向镜头，双脚前后错开',
    '从肩膀上方回头看镜头',
    '手臂自然垂下',
  ]),
  shade('遮阳', 'assets/poses/02-遮阳.png', 810 / 1940, .60, [
    '一只手抬到眉毛上方',
    '手掌微弯，像在挡阳光',
    '另一只手放松垂下',
  ]),
  walk('迈步', 'assets/poses/03-迈步.png', 806 / 1952, .60, [
    '朝镜头斜前方迈出一步',
    '让后脚跟自然抬起',
    '双臂随步伐轻摆',
  ]),
  fold('交叉抱臂', 'assets/poses/04-交叉抱臂.png', 807 / 1949, .60, [
    '身体稍微转向一侧',
    '两臂在胸前轻轻交叠',
    '肩膀放松，双脚分开',
  ]),
  wave('踮脚挥手', 'assets/poses/05-踮脚挥手.png', 806 / 1952, .60, [
    '侧身站好，后脚轻轻踮起',
    '一只手抬到肩旁挥手',
    '另一只手搭在腰间',
  ]),
  crossLegs('盘腿坐', 'assets/poses/06-盘腿坐.png', 1130 / 1392, .45, [
    '面向镜头盘腿坐下',
    '双手轻放在两膝上',
    '挺直身体，放松肩膀',
  ]),
  sideSit('侧坐撑地', 'assets/poses/07-侧坐撑地.png', 1594 / 987, .40, [
    '坐下，把双腿收向同一侧',
    '身后一只手轻轻撑地',
    '另一只手搭在腿上',
  ]),
  kneel('单膝跪姿', 'assets/poses/08-单膝跪姿.png', 1056 / 1490, .48, [
    '单膝跪地，另一只脚踩稳',
    '前臂搭在抬起的膝盖上',
    '上身略向镜头侧转',
  ]),
  stretch('伸展', 'assets/poses/09-伸展.png', 806 / 1952, .65, [
    '双手举过头顶，轻轻相握',
    '上身向一侧舒展',
    '双脚踩稳，保持平衡',
  ]),
  lean('背手前倾', 'assets/poses/10-背手前倾.png', 806 / 1952, .54, [
    '侧身站立，双手在背后相握',
    '从髋部轻轻向前倾',
    '抬起下巴，放松双肩',
  ]);

  const Pose(
    this.title,
    this.asset,
    this.aspectRatio,
    this.heightFraction,
    this.steps,
  );
  final String title, asset;
  final double aspectRatio, heightFraction;
  final List<String> steps;
  String get tip => steps.first;
}

class Viewfinder extends StatefulWidget {
  const Viewfinder({super.key, required this.demo});
  final bool demo;
  @override
  State<Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<Viewfinder> {
  Pose pose = Pose.crouch;
  bool preview = false;
  static const centered = Offset(.5, .5);
  Offset position = centered;
  double scale = 1;
  double startScale = 1;

  ShootSession? session;
  String? photo;
  bool working = false, mirrored = false, saved = false, grid = false;
  double opacity = .56, angle = 0, startAngle = 0;
  int step = 0, countdown = 0;
  bool selfTimer = false;
  @override
  void initState() {
    super.initState();
    if (!widget.demo) startCamera();
  }

  void startCamera() {
    session = ShootSession()..addListener(refresh);
  }

  void refresh() {
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
      final file = await camera?.takePicture();
      if (mounted) {
        setState(() {
          photo = file?.path;
          preview = true;
          saved = false;
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
      await Gal.putImage(photo!);
      if (mounted) setState(() => saved = true);
    } catch (_) {
      notice('保存失败，请检查相册权限后重试');
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
                          Expanded(
                            child: Image.asset(
                              p.asset,
                              cacheWidth: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
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
      setState(() {
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
                            child: Image.asset(pose.asset, fit: BoxFit.contain),
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
                          const Text(
                            'PicPic',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 6)],
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
                                  onPressed: choosePose,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  icon: Image.asset(
                                    pose.asset,
                                    height: 33,
                                    width: 33,
                                  ),
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
