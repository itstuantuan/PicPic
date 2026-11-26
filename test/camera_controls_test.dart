import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpic/features/camera.dart';

class CameraHarness extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final flash = <FlashMode>[];
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => 1;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async =>
      flash.add(mode);
  @override
  Future<XFile> takePicture(int cameraId) async =>
      XFile(File('assets/street.jpg').absolute.path);
  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  testWidgets('后置镜头切换闪光，拍摄后的分享入口仅作用于原片', (tester) async {
    final original = CameraPlatform.instance;
    final harness = CameraHarness();
    CameraPlatform.instance = harness;
    addTearDown(() => CameraPlatform.instance = original);
    await tester.pumpWidget(const MaterialApp(home: Viewfinder(demo: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('开启闪光灯'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭闪光灯'));
    await tester.pumpAndSettle();
    expect(harness.flash, [FlashMode.always, FlashMode.off]);
    expect(find.text('分享原片'), findsNothing);
    await tester.tap(find.bySemanticsLabel('拍照'));
    await tester.pumpAndSettle();
    expect(find.text('分享原片'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    MethodCall? sent;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return '';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.tap(find.text('分享原片'));
    await tester.pumpAndSettle();
    expect(sent?.method, 'share');
    expect(sent?.arguments['paths'], [File('assets/street.jpg').absolute.path]);
    await tester.tap(find.text('返回取景'));
    await tester.pumpAndSettle();
    expect(find.text('分享原片'), findsNothing);
  });
}
