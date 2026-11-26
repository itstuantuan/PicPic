import 'package:flutter/material.dart';
import 'package:picpic/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('切换姿势和成片预览', (tester) async {
    await tester.pumpWidget(const PoseDemo(demo: true));
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
    await tester.pumpWidget(const PoseDemo(demo: true));
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
