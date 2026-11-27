import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'catalog.dart';
import 'notebook.dart';

const categories = [
  '全部',
  '站姿',
  '坐姿',
  '自拍',
  '背影',
  '情侣',
  '双人',
  '行走',
  '旅行',
  '街拍',
  '人像',
];
const inset = EdgeInsets.fromLTRB(16, 8, 16, 24);
const cardColor = Color(0xff272726);
Widget heading(String s) => Padding(
  padding: const EdgeInsets.only(top: 22, bottom: 12),
  child: Text(
    s,
    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
  ),
);
Widget sectionTitle(String s) =>
    Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
Widget surface(Widget child) => DecoratedBox(
  decoration: BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(16),
  ),
  child: child,
);
Widget entry(IconData icon, String title, VoidCallback action) => ListTile(
  leading: Icon(icon),
  title: Text(title),
  trailing: const Icon(Icons.chevron_right),
  onTap: action,
);

class PoseCard extends StatelessWidget {
  const PoseCard(this.p, {super.key});
  final Pose p;
  @override
  Widget build(BuildContext c) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => c.push('/pose/${p.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: surface(
              Padding(
                padding: const EdgeInsets.all(12),
                child: PoseImage(p, thumbnail: true),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          '${p.category}  ·  ${p.people} 人',
          style: Theme.of(c).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

Widget strip(List<Pose> list) => SizedBox(
  height: 178,
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: list.length,
    separatorBuilder: (_, _) => const SizedBox(width: 10),
    itemBuilder: (_, i) => SizedBox(width: 125, child: PoseCard(list[i])),
  ),
);
List<Pose> used(NotebookData data, {bool popular = false}) {
  final rows = [...data.uses];
  if (popular) {
    rows.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }
  return rows
      .map((r) => Pose.find(r['id'] as String))
      .whereType<Pose>()
      .toList();
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final data = ref.watch(notebookProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PicPic',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () => c.push('/settings'),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '个人中心',
            onPressed: () => c.go('/me'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: inset,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              alignment: Alignment.bottomLeft,
              children: [
                Image.asset(
                  'assets/street.jpg',
                  width: double.infinity,
                  height: 290,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, .35),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: FilledButton.icon(
                    onPressed: () => c.push('/camera/crouch'),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('开始拍摄'),
                  ),
                ),
              ],
            ),
          ),
          heading('今日推荐'),
          strip([Pose.crouch, Pose.anns12, Pose.walk, Pose.stand, Pose.anns07]),
          heading('按场景找姿势'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['街道', '长椅', '公园', '室内', '台阶', '海滩'])
                ActionChip(
                  label: Text(s),
                  onPressed: () =>
                      c.push('/browse?filter=${Uri.encodeComponent(s)}'),
                ),
            ],
          ),
          if (data != null && data.uses.isNotEmpty) ...[
            heading('最近使用'),
            strip(used(data).take(8).toList()),
            heading('本机热门'),
            strip(used(data, popular: true).take(6).toList()),
          ],
          entry(Icons.event_note, '拍摄计划', () => c.push('/plans')),
          entry(
            Icons.add_photo_alternate_outlined,
            '自定义姿势',
            () => c.push('/custom'),
          ),
        ],
      ),
    );
  }
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.initial = '全部', this.standalone = false});
  final String initial;
  final bool standalone;
  @override
  ConsumerState<LibraryPage> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<LibraryPage> {
  late String filter = widget.initial;
  String query = '';
  bool popular = false;
  @override
  Widget build(BuildContext c) {
    final data = ref.watch(notebookProvider).asData?.value;
    final counts = {
      for (final r in data?.uses ?? <Map<String, Object?>>[])
        r['id']: r['count'] as int,
    };
    final list = Pose.values.where((p) {
      final matches = switch (filter) {
        '全部' => true,
        '收藏' => data?.favorites.contains(p.id) ?? false,
        '最近' => counts.containsKey(p.id),
        _ => p.category == filter || p.scene.contains(filter),
      };
      return matches &&
          [
            p.title,
            p.category,
            p.scene,
            ...p.steps,
          ].join(' ').contains(query.trim());
    }).toList();
    if (popular) {
      list.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    } else if (filter == '最近' && data != null) {
      final recent = used(data);
      list.sort((a, b) => recent.indexOf(a).compareTo(recent.indexOf(b)));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.standalone ? widget.initial : '姿势库'),
        actions: [
          IconButton(
            tooltip: '按本机使用次数排序',
            isSelected: popular,
            icon: const Icon(Icons.sort),
            selectedIcon: const Icon(Icons.trending_up),
            onPressed: () => setState(() => popular = !popular),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (s) => setState(() => query = s),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索动作或场景',
              ),
            ),
          ),
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in {...categories, '收藏', '最近', widget.initial})
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: filter == s,
                      onSelected: (_) => setState(() => filter = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('暂无匹配姿势'))
                : GridView.builder(
                    padding: inset,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          mainAxisExtent: 215,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 15,
                        ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => PoseCard(list[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class PoseDetail extends ConsumerWidget {
  const PoseDetail(this.p, {super.key});
  final Pose p;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final saved =
        ref.watch(notebookProvider).asData?.value.favorites.contains(p.id) ??
        false;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.category),
        actions: [
          IconButton(
            tooltip: saved ? '取消收藏' : '收藏',
            onPressed: () => ref.read(notebookProvider.notifier).favorite(p.id),
            icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      body: ListView(
        padding: inset,
        children: [
          surface(
            Padding(
              padding: const EdgeInsets.all(20),
              child: PoseImage(p, height: 290),
            ),
          ),
          heading(p.title),
          Text('${p.people} 人   ·   ${p.difficulty}   ·   ${p.scene}'),
          heading('动作指导'),
          for (final (i, s) in p.steps.indexed)
            ListTile(dense: true, leading: Text('${i + 1}'), title: Text(s)),
          heading('拍摄角度'),
          Text(p.advice),
          TextButton.icon(
            onPressed: () => c.push('/plans/new?pose=${p.id}'),
            icon: const Icon(Icons.playlist_add),
            label: const Text('用此姿势新建计划'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => c.push('/camera/${p.id}'),
            icon: const Icon(Icons.camera_alt),
            label: const Text('开始拍摄'),
          ),
        ),
      ),
    );
  }
}

class CreatePage extends StatelessWidget {
  const CreatePage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('创作')),
    body: ListView(
      padding: inset,
      children: [
        entry(Icons.accessibility_new, '自定义姿势', () => c.push('/custom')),
        entry(Icons.photo_filter, '照片 Studio', () => c.push('/ai/edit')),
        entry(Icons.landscape_outlined, '场景推荐', () => c.push('/ai/scene')),
        entry(Icons.history, '生成历史', () => c.push('/ai/history')),
      ],
    ),
  );
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final data = ref.watch(notebookProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: inset,
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(data?.name ?? '摄影爱好者'),
            subtitle: const Text('本机资料'),
            onTap: () => c.push('/settings'),
          ),
          entry(
            Icons.favorite_border,
            '我的收藏',
            () => c.push('/browse?filter=${Uri.encodeComponent('收藏')}'),
          ),
          entry(
            Icons.history,
            '最近使用',
            () => c.push('/browse?filter=${Uri.encodeComponent('最近')}'),
          ),
          entry(Icons.accessibility_new, '我的自定义姿势', () => c.push('/custom')),
          entry(Icons.collections_outlined, '我的照片', () => c.push('/photos')),
          entry(Icons.history, 'AI 生成历史', () => c.push('/ai/history')),
          entry(Icons.event_note, '拍摄计划', () => c.push('/plans')),
          entry(Icons.settings_outlined, '设置', () => c.push('/settings')),
        ],
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      children: [
        entry(Icons.edit_outlined, '编辑本机昵称', () async {
          String name = ref.read(notebookProvider).asData?.value.name ?? '';
          final value = await showDialog<String>(
            context: c,
            builder: (ctx) => AlertDialog(
              title: const Text('本机昵称'),
              content: TextFormField(
                initialValue: name,
                maxLength: 24,
                onChanged: (s) => name = s,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (name.trim().isNotEmpty) Navigator.pop(ctx, name.trim());
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          );
          if (value != null && c.mounted) {
            await ref.read(notebookProvider.notifier).rename(value);
          }
        }),
        const ExpansionTile(
          title: Text('隐私与数据'),
          children: [
            ListTile(title: Text('收藏、计划和使用记录保存在本机。相机照片仅在你选择保存时写入系统相册。')),
          ],
        ),
        const ExpansionTile(
          title: Text('使用说明'),
          children: [ListTile(title: Text('在安全的位置模仿姿势。按设备能力选择动作，拍摄他人前请征得同意。'))],
        ),
      ],
    ),
  );
}

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final plans = ref.watch(notebookProvider).asData?.value.plans ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄计划')),
      body: ListView(
        padding: inset,
        children: [
          FilledButton.icon(
            onPressed: () => c.push('/plans/new'),
            icon: const Icon(Icons.add),
            label: const Text('新建拍摄计划'),
          ),
          for (final p in plans)
            ListTile(
              title: Text(p['title'] as String),
              subtitle: Text(p['location'] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => c.push('/plans/${p['id']}'),
            ),
        ],
      ),
    );
  }
}

class NewPlanPage extends ConsumerStatefulWidget {
  const NewPlanPage({super.key, this.initial});
  final String? initial;
  @override
  ConsumerState<NewPlanPage> createState() => _NewPlanPageState();
}

class _NewPlanPageState extends ConsumerState<NewPlanPage> {
  String title = '', location = '';
  late final selected = <String>{if (widget.initial != null) widget.initial!};
  bool saving = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('新建计划')),
    body: ListView(
      padding: inset,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: '主题'),
          onChanged: (s) => setState(() => title = s.trim()),
        ),
        TextField(
          decoration: const InputDecoration(labelText: '地点'),
          onChanged: (s) => location = s.trim(),
        ),
        heading('选择姿势'),
        for (final p in Pose.values)
          CheckboxListTile(
            value: selected.contains(p.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                selected.add(p.id);
              } else {
                selected.remove(p.id);
              }
            }),
            title: Text(p.title),
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: title.isEmpty || selected.isEmpty || saving
              ? null
              : () async {
                  setState(() => saving = true);
                  try {
                    final ordered = selected.toList()
                      ..sort(
                        (a, b) =>
                            Pose.find(a)!.category
                                .compareTo(Pose.find(b)!.category),
                      );
                    final id = await ref
                        .read(notebookProvider.notifier)
                        .plan(title, location, ordered);
                    if (c.mounted) c.replace('/plans/$id');
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          child: Text('保存计划（${selected.length}）'),
        ),
      ),
    ),
  );
}

class PlanDetail extends ConsumerWidget {
  const PlanDetail(this.id, {super.key});
  final int id;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final data = ref.watch(notebookProvider).asData?.value;
    final plan = data?.plans.where((r) => r['id'] == id).firstOrNull;
    final rows = data?.items.where((r) => r['plan'] == id) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(plan?['title'] as String? ?? '拍摄计划')),
      body: ListView(
        padding: inset,
        children: [
          Text(plan?['location'] as String? ?? ''),
          heading('拍摄顺序'),
          for (final row in rows)
            ListTile(
              leading: Icon(
                row['done'] == 1 ? Icons.check_circle : Icons.circle_outlined,
              ),
              title: Text(Pose.find(row['pose'] as String)!.title),
              trailing: const Icon(Icons.camera_alt_outlined),
              onTap: () => c.push('/camera/${row['pose']}?plan=$id'),
            ),
        ],
      ),
    );
  }
}

class PhotoPage extends ConsumerWidget {
  const PhotoPage({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final photos = ref.watch(notebookProvider).asData?.value.photos ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('我的照片')),
      body: photos.isEmpty
          ? const Center(child: Text('保存的拍摄照片会显示在这里'))
          : GridView.extent(
              maxCrossAxisExtent: 180,
              children: [
                for (final r in photos)
                  InkWell(
                    onTap: () => showDialog(
                      context: c,
                      builder: (ctx) => Dialog(
                        child: Image.file(
                          File(r['path'] as String),
                          errorBuilder: (_, _, _) =>
                              const Text('请在系统相册中查看已保存的照片'),
                        ),
                      ),
                    ),
                    child: Image.file(
                      File(r['path'] as String),
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.photo_outlined),
                    ),
                  ),
              ],
            ),
    );
  }
}
