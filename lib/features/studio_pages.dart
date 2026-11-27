import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'cloud_service.dart';

const taskStates = {
  'queued': '排队中',
  'running': '处理中',
  'done': '已完成',
  'failed': '失败',
};
String failure(Object e) => e is CloudIssue ? e.message : '操作失败，请检查网络、权限或照片后重试';

class SceneResults extends StatelessWidget {
  const SceneResults(this.scene, {super.key});
  final String scene;
  @override
  Widget build(BuildContext context) {
    final tag = switch (scene) {
      '墙壁' => '街道',
      '咖啡馆' => '长椅',
      _ => scene,
    };
    final poses = Pose.values.where((p) => p.scene.contains(tag)).take(6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scene == '其他' ? '未能确定场景' : '识别到$scene',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final pose in poses)
          ListTile(
            leading: PoseImage(pose, height: 50, width: 40),
            title: Text(pose.title),
            onTap: () => context.push('/pose/${pose.id}'),
          ),
        if (poses.isEmpty)
          TextButton(
            onPressed: () => context.go('/poses'),
            child: const Text('浏览姿势库'),
          ),
      ],
    );
  }
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key, required this.scene});
  final bool scene;
  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final prompt = TextEditingController();
  String style = styles.first;
  XFile? file;
  bool busy = false;
  String? error, scene, id;
  bool get local => widget.scene && Platform.isIOS;
  Future<void> pick(ImageSource source) async {
    setState(() => busy = true);
    try {
      final selected = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (selected != null && mounted) {
        setState(() {
          file = selected;
          scene = null;
          error = null;
          id = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start() async {
    final pic = file;
    if (pic == null || busy) return;
    setState(() {
      busy = true;
      error = null;
      scene = null;
    });
    try {
      if (local) {
        final labels = await const MethodChannel('picpic/scene')
            .invokeListMethod<String>('classify', pic.path);
        if (mounted) setState(() => scene = sceneFromLabels(labels ?? []));
      } else {
        if (await pic.length() > 8 * 1024 * 1024) {
          throw const CloudIssue('图片超过 8 MB，请选择较小的图片');
        }
        id ??= const Uuid().v4();
        final result = await StudioService().submit(
          id!,
          widget.scene ? 'scene' : 'edit',
          widget.scene ? '' : style,
          prompt.text,
          await pic.readAsBytes(),
        );
        id = null;
        if (mounted) await context.push('/ai/task/${result['id']}');
      }
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.scene ? '场景推荐' : '照片 Studio'),
      actions: [
        IconButton(
          onPressed: () => c.push('/ai/history'),
          tooltip: '生成历史',
          icon: const Icon(Icons.history),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(file!.path),
              height: 260,
              fit: BoxFit.contain,
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('选照片'),
            ),
            if (widget.scene)
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍摄场景'),
              ),
          ],
        ),
        if (!widget.scene) ...[
          Wrap(
            spacing: 6,
            children: [
              for (final item in styles)
                ChoiceChip(
                  label: Text(item),
                  selected: item == style,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          style = item;
                          id = null;
                        }),
                ),
            ],
          ),
          TextField(
            controller: prompt,
            enabled: !busy,
            maxLength: 600,
            maxLines: 2,
            onChanged: (_) => id = null,
            decoration: const InputDecoration(labelText: '补充描述（可选）'),
          ),
        ],
        if (!local && !StudioService.configured) const Text('云端服务尚未配置'),
        FilledButton(
          onPressed:
              file == null || busy || (!local && !StudioService.configured)
              ? null
              : start,
          child: Text(
            local
                ? '在本机识别场景'
                : widget.scene
                ? '上传并识别场景'
                : '上传并生成',
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (scene != null) SceneResults(scene!),
      ],
    ),
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryState();
}

class _HistoryState extends State<HistoryPage> {
  late Future<List<Job>> items;
  void load() {
    items = StudioService().history();
  }

  @override
  void initState() {
    super.initState();
    if (StudioService.configured) load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('生成历史')),
    body: !StudioService.configured
        ? const Center(child: Text('云端服务尚未配置'))
        : FutureBuilder(
            future: items,
            builder: (c, s) {
              if (s.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(load),
                    child: Text('${failure(s.error!)} · 重试'),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) return const Center(child: Text('暂无生成任务'));
              return ListView(
                children: [
                  for (final job in s.data!)
                    ListTile(
                      title: Text(
                        job['kind'] == 'scene' ? '场景识别' : job['style'],
                      ),
                      subtitle: Text(taskStates[job['state']] ?? ''),
                      onTap: () async {
                        await c.push('/ai/task/${job['id']}');
                        if (mounted) setState(load);
                      },
                    ),
                ],
              );
            },
          ),
  );
}

class JobPage extends StatefulWidget {
  const JobPage(this.id, {super.key});
  final String id;
  @override
  State<JobPage> createState() => _JobState();
}

class _JobState extends State<JobPage> {
  final service = StudioService();
  Job? job;
  Uint8List? original, result;
  bool showOriginal = false, busy = false, exporting = false;
  String? error;
  Future<void> load({bool retry = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var current = retry
          ? await service.retry(job!)
          : await service.detail(widget.id);
      while (mounted) {
        setState(() => job = current);
        if (!['queued', 'running'].contains(current['state'])) break;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        current = await service.detail(widget.id);
      }
      if (!mounted) return;
      if (current['state'] == 'done' && current['kind'] == 'edit') {
        final images = await Future.wait([
          service.image(widget.id, 'source'),
          service.image(widget.id, 'result'),
        ]);
        if (mounted) {
          setState(() {
            original = images[0];
            result = images[1];
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(BuildContext anchor, bool share) async {
    final box = anchor.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(result!, mimeType: 'image/jpeg')],
            fileNameOverrides: ['PicPic.jpg'],
            sharePositionOrigin: origin,
          ),
        );
      } else {
        await Gal.putImageBytes(result!, name: 'PicPic-${widget.id}');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已保存到相册')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure(e))));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(job?['kind'] == 'scene' ? '识别结果' : '生成结果')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (job != null) Text(taskStates[job!['state']] ?? ''),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          TextButton(
            onPressed: busy ? null : load,
            child: Text('$error · 重新加载'),
          ),
        if (job?['state'] == 'failed') ...[
          Text(job?['error'] ?? '任务失败'),
          FilledButton(
            onPressed: busy ? null : () => load(retry: true),
            child: const Text('重新生成'),
          ),
        ],
        if (job?['scene'] != null) SceneResults(job!['scene']),
        if (result != null) ...[
          Image.memory(
            showOriginal ? original! : result!,
            height: 340,
            fit: BoxFit.contain,
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('原图')),
              ButtonSegment(value: false, label: Text('生成图')),
            ],
            selected: {showOriginal},
            onSelectionChanged: (s) => setState(() => showOriginal = s.single),
          ),
          Builder(
            builder: (anchor) => Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: exporting ? null : () => export(anchor, false),
                  child: const Text('保存生成图'),
                ),
                OutlinedButton(
                  onPressed: exporting ? null : () => export(anchor, true),
                  child: const Text('分享生成图'),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
