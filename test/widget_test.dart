import 'package:picpic/features/cloud_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpic/features/notebook.dart';
import 'package:picpic/main.dart';
import 'package:flutter/material.dart';
import 'package:picpic/features/camera.dart';
import 'package:picpic/features/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryNotebook extends Notebook {
  @override
  Future<NotebookData> build() async =>
      const NotebookData('相册', {}, [], [], [], []);
  @override
  Future<void> use(String id) async {}
}

void main() {
  testWidgets('创作页进入修图和历史，未配置时阻止上传', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notebookProvider.overrideWith(MemoryNotebook.new)],
        child: const PicPic(demo: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('照片 Studio'));
    await tester.pumpAndSettle();
    for (final label in styles) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('云端服务尚未配置'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '上传并生成'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('生成历史'));
    await tester.pumpAndSettle();
    expect(find.text('云端服务尚未配置'), findsOneWidget);
  });
  testWidgets('从首页搜索姿势并进入对应取景器', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notebookProvider.overrideWith(MemoryNotebook.new)],
        child: const PicPic(demo: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('姿势'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), Pose.stand.title);
    await tester.pumpAndSettle();
    await tester.tap(find.text(Pose.stand.title).last);
    await tester.pumpAndSettle();
    expect(find.text('动作指导'), findsOneWidget);
    await tester.tap(find.text('开始拍摄'));
    await tester.pumpAndSettle();
    expect(find.text(Pose.stand.tip), findsOneWidget);
  });
  testWidgets('切换姿势和成片预览', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Viewfinder(demo: true)));
    final viewCenter = tester.getCenter(find.byType(Scaffold));
    Finder guide(Pose pose) => find.descendant(
      of: find.byType(Opacity),
      matching: find.image(AssetImage(pose.asset)),
    );
    expect(tester.getCenter(guide(Pose.crouch)), viewCenter);
    await tester.drag(guide(Pose.crouch), const Offset(40, 25));
    await tester.tap(find.byTooltip('选择姿势'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('侧身扶头'));
    await tester.pumpAndSettle();
    expect(find.text(Pose.stand.tip), findsOneWidget);
    expect(tester.getCenter(guide(Pose.stand)), viewCenter);
    await tester.tap(find.bySemanticsLabel('模拟拍照'));
    await tester.pumpAndSettle();
    expect(find.text('成片预览'), findsOneWidget);
    expect(guide(Pose.stand), findsNothing);
    await tester.tap(find.text('返回取景'));
    await tester.pumpAndSettle();
    expect(find.text(Pose.stand.tip), findsOneWidget);
  });
  testWidgets('可滚动选中台阶错层坐并查看下一步', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Viewfinder(demo: true)));
    await tester.tap(find.byTooltip('选择姿势'));
    await tester.pumpAndSettle();
    final last = find.text('台阶错层坐');
    await tester.scrollUntilVisible(
      last.hitTestable(),
      180,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text(Pose.anns12.tip), findsOneWidget);
    await tester.tap(find.text(Pose.anns12.tip));
    await tester.pump();
    expect(find.text(Pose.anns12.steps[1]), findsOneWidget);
  });
}
