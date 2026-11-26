import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpic/features/catalog.dart';
import 'package:picpic/features/notebook.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('100 个姿势各自引用可加载的离线素材', () async {
    await Pose.load();
    await Pose.load();
    expect(Pose.values.map((p) => p.id).toSet().length, 100);
    expect(Pose.values.map((p) => p.asset).toSet().length, 100);
    for (final pose in Pose.values) {
      expect((await rootBundle.load(pose.asset)).lengthInBytes, greaterThan(0));
    }
  });
  test('版本一数据库升级后收藏仍在，自定义骨架可重新加载', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('picpic-upgrade');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/test.sqlite';
    final previous = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE favorites(id TEXT PRIMARY KEY)');
          await db.insert('favorites', {'id': 'stand'});
        },
      ),
    );
    await previous.close();
    final db = await openNotebook(factory: databaseFactoryFfi, path: path);
    expect((await db.query('favorites')).single['id'], 'stand');
    await db.insert('custom_poses', {
      'id': 'custom_test',
      'name': '试姿势',
      'aspect': .6,
      'svg': '<svg/>',
      'rig': '{"lw":[0.2,0.4]}',
    });
    await db.close();
    final reopened = await openNotebook(
      factory: databaseFactoryFfi,
      path: path,
    );
    Pose.registerCustom((await reopened.query('custom_poses')).single);
    expect(Pose.find('custom_test')!.title, '试姿势');
    expect(Pose.rigs['custom_test']!['lw']!.dy, .4);
    Pose.values.removeWhere((p) => p.id == 'custom_test');
    Pose.rigs.remove('custom_test');
    await reopened.close();
  });
  test('重启后保留收藏、计划进度与原片副本', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('picpic-test');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = '${dir.path}/notes.sqlite';
    Future<ProviderContainer> start() async {
      final db = await openNotebook(factory: databaseFactoryFfi, path: dbPath);
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          photoDirectoryProvider.overrideWithValue(() async => dir),
        ],
      );
    }

    Future<void> stop(ProviderContainer c) async {
      final db = c.read(databaseProvider);
      c.dispose();
      await db.close();
    }

    final first = await start();
    await first.read(notebookProvider.future);
    final notes = first.read(notebookProvider.notifier);
    await notes.favorite('walk');
    await notes.use('walk');
    await notes.use('walk');
    final plan = await notes.plan('周末', '街道', ['walk', 'sit']);
    final original = File('${dir.path}/camera.jpg');
    await original.writeAsBytes([1, 2, 3]);
    await notes.captured('walk', original.path, plan);
    await original.delete();
    await stop(first);
    final next = await start();
    final data = await next.read(notebookProvider.future);
    expect(data.favorites, contains('walk'));
    expect(data.uses.single['count'], 2);
    expect(data.items.map((i) => i['done']), [1, 0]);
    expect(await File(data.photos.single['path'] as String).readAsBytes(), [
      1,
      2,
      3,
    ]);
    await stop(next);
  });
}
