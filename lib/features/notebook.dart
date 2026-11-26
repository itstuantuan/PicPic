import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

final databaseProvider = Provider<Database>(
  (ref) => throw StateError('数据库尚未初始化'),
);
final photoDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);
final notebookProvider = AsyncNotifierProvider<Notebook, NotebookData>(
  Notebook.new,
);

class NotebookData {
  const NotebookData(
    this.name,
    this.favorites,
    this.uses,
    this.plans,
    this.items,
    this.photos,
  );
  final String name;
  final Set<String> favorites;
  final List<Map<String, Object?>> uses, plans, items, photos;
}

const customPoseSchema =
    'CREATE TABLE custom_poses(id TEXT PRIMARY KEY, name TEXT NOT NULL, aspect REAL NOT NULL, svg TEXT NOT NULL, rig TEXT NOT NULL)';
Future<Database> openNotebook({
  DatabaseFactory? factory,
  String path = 'picpic.sqlite',
}) => (factory ?? databaseFactory).openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: 2,
    onUpgrade: (db, old, v) async {
      if (old < 2) await db.execute(customPoseSchema);
    },
    onCreate: (db, v) async {
      await db.execute(customPoseSchema);
      await db.execute('CREATE TABLE favorites(id TEXT PRIMARY KEY)');
      await db.execute(
        'CREATE TABLE usage(id TEXT PRIMARY KEY, count INTEGER NOT NULL,last INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE profile(id INTEGER PRIMARY KEY, name TEXT)',
      );
      await db.execute(
        'CREATE TABLE plans(id INTEGER PRIMARY KEY, title TEXT, location TEXT)',
      );
      await db.execute(
        'CREATE TABLE items(plan INTEGER, pose TEXT, seq INTEGER, done INTEGER DEFAULT 0, PRIMARY KEY(plan,pose))',
      );
      await db.execute(
        'CREATE TABLE photos(id INTEGER PRIMARY KEY, path TEXT, pose TEXT, plan INTEGER)',
      );
    },
  ),
);

class Notebook extends AsyncNotifier<NotebookData> {
  Database get db => ref.read(databaseProvider);
  @override
  Future<NotebookData> build() => read();
  Future<NotebookData> read() async {
    final user = await db.query('profile');
    final rows = await db.query('photos', orderBy: 'id DESC');
    final photos = <Map<String, Object?>>[];
    if (rows.isNotEmpty) {
      final directory = await ref.read(photoDirectoryProvider)();
      for (final row in rows) {
        final stored = row['path'] as String;
        photos.add({
          ...row,
          'path': paths.isAbsolute(stored)
              ? stored
              : paths.join(directory.path, stored),
        });
      }
    }
    return NotebookData(
      user.isEmpty ? '摄影爱好者' : user.first['name'] as String,
      (await db.query('favorites')).map((r) => r['id'] as String).toSet(),
      await db.query('usage', orderBy: 'last DESC'),
      await db.query('plans', orderBy: 'id DESC'),
      await db.query('items', orderBy: 'seq'),
      photos,
    );
  }

  Future<void> refresh() async {
    state = AsyncData(await read());
  }

  Future<void> favorite(String id) async {
    await db.transaction((t) async {
      if (await t.delete('favorites', where: 'id=?', whereArgs: [id]) == 0) {
        await t.insert('favorites', {'id': id});
      }
    });
    await refresh();
  }

  Future<void> use(String id) async {
    await db.rawInsert(
      'INSERT INTO usage VALUES(?,1,?) ON CONFLICT(id) DO UPDATE SET count=count+1,last=excluded.last',
      [id, DateTime.now().microsecondsSinceEpoch],
    );
    await refresh();
  }

  Future<void> rename(String value) async {
    await db.insert('profile', {
      'id': 1,
      'name': value.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await refresh();
  }

  Future<int> plan(String title, String location, List<String> poses) async {
    final id = await db.transaction((t) async {
      final id = await t.insert('plans', {
        'title': title,
        'location': location,
      });
      for (final (i, pose) in poses.indexed) {
        await t.insert('items', {'plan': id, 'pose': pose, 'seq': i});
      }
      return id;
    });
    await refresh();
    return id;
  }

  Future<void> captured(String pose, String path, int? plan) async {
    final directory = await ref.read(photoDirectoryProvider)();
    final folder = await Directory(paths.join(directory.path, 'photos'))
        .create(recursive: true);
    final target = File(
      paths.join(
        folder.path,
        '${DateTime.now().microsecondsSinceEpoch}${paths.extension(path)}',
      ),
    );
    try {
      await File(path).copy(target.path);
      await db.transaction((t) async {
        await t.insert('photos', {
          'pose': pose,
          'path': paths.relative(target.path, from: directory.path),
          'plan': plan,
        });
        if (plan != null) {
          await t.update(
            'items',
            {'done': 1},
            where: 'plan=? AND pose=?',
            whereArgs: [plan, pose],
          );
        }
      });
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
    await refresh();
  }
}
