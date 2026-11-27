import 'package:flutter_test/flutter_test.dart';
import 'package:picpic/features/catalog.dart';
import 'package:picpic/features/cloud_service.dart';
import 'package:picpic/features/pose_vision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('双人按取景位置匹配，两人检测顺序交换时评分一致', () async {
    await Pose.load();
    expect(Pose.duoRigs.length, 20);
    final targets = Pose.duoRigs.values.first;
    final aspect = Pose.find(Pose.duoRigs.keys.first)!.aspectRatio;
    String match(List<Rig> input) => matchPeople(
      targets,
      input,
      aspect,
      aspect,
      mirror: false,
      previewMirror: false,
      angle: 0,
    );
    expect(match(targets), contains('左位 · 100%'));
    expect(match(targets.reversed.toList()), match(targets));
    expect(match([targets.first]), contains('1/2'));
    expect(match([targets.first, targets.first]), isNot(contains('%')));
  });
  test('视觉模型标签映射，无法确定时不给出场景', () {
    expect(sceneFromLabels(['people', 'staircase']), '台阶');
    expect(sceneFromLabels(['adult', 'arch']), '建筑');
    expect(sceneFromLabels(['people']), '其他');
  });
}
