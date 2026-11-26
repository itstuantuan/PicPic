import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Orders device opens and releases when the app changes state or lens.
class ShootSession extends ChangeNotifier with WidgetsBindingObserver {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  CameraLensDirection lens = CameraLensDirection.back;
  String? error;
  bool _closed = false;
  int _revision = 0;
  Future<void> _queue = Future.value();

  ShootSession() {
    WidgetsBinding.instance.addObserver(this);
    configure();
  }

  void configure({bool active = true}) {
    final revision = ++_revision;
    _queue = _queue.then((_) async {
      final old = controller;
      controller = null;
      if (!_closed) notifyListeners();
      await old?.dispose();
      if (!active || _closed || revision != _revision) return;
      CameraController? next;
      try {
        cameras = await availableCameras();
        if (cameras.isEmpty) throw CameraException('NoCamera', '');
        final device = cameras.firstWhere(
          (c) => c.lensDirection == lens,
          orElse: () => cameras.first,
        );
        lens = device.lensDirection;
        next = CameraController(
          device,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await next.initialize();
        if (_closed || revision != _revision) {
          await next.dispose();
          return;
        }
        controller = next;
        error = null;
      } catch (e) {
        await next?.dispose();
        if (_closed || revision != _revision) return;
        error = e is CameraException && e.code.contains('Access')
            ? '相机权限未开启，请在系统设置中允许访问。'
            : '当前设备的相机不可用';
      }
      if (!_closed) notifyListeners();
    });
  }

  void flip() {
    lens = lens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    configure();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) configure();
    if (state == AppLifecycleState.paused) configure(active: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    configure(active: false);
    super.dispose();
  }
}
