
import 'package:flutter_test/flutter_test.dart';
import 'package:picpic/features/catalog.dart';
import 'package:picpic/features/pose_vision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('参考骨架保留宽高比，低可见度时不给分', () async {
    await Pose.load();
    final target = Pose.rigs['study_01']!;
    final aspect = Pose.find('study_01')!.aspectRatio;
    expect(compareRig(target, target, aspect, aspect), contains('100%'));
    final moved = Map.of(target)
      ..['lw'] = target['lw']! + const Offset(.5, .45);
    expect(compareRig(target, moved, aspect, aspect), isNot(contains('100%')));
    expect(compareRig(target, {}, aspect, aspect), isNot(contains('%')));
    expect(Pose.rigs.length, 79);
  });
}
