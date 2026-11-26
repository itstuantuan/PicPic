import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'catalog.dart';
import 'notebook.dart';
import 'pose_vision.dart';

class CustomPosePage extends ConsumerStatefulWidget {
  const CustomPosePage({super.key});
  @override
  ConsumerState<CustomPosePage> createState() => _CustomPoseState();
}

class _CustomPoseState extends ConsumerState<CustomPosePage> {
  final name = TextEditingController();
  ExtractedPose? result;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        maxHeight: 1400,
        requestFullMetadata: false,
      );
      if (file == null) return;
      if (!mounted) return;
      setState(() => result = null);
      final pose = await extractPose(file.path);
      if (mounted) setState(() => result = pose);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '读取照片或运行模型失败，请换一张照片重试');
      debugPrint('PicPic pose extraction: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final model = result;
    if (model == null || busy) return;
    setState(() => busy = true);
    try {
      final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
      final row = {
        'id': id,
        'name': name.text.trim().isEmpty ? '我的姿势' : name.text.trim(),
        'aspect': model.aspect,
        'svg': model.svg,
        'rig': jsonEncode(encodeRig(model.rig)),
      };
      final notebook = ref.read(notebookProvider.notifier);
      await ref.read(databaseProvider).insert('custom_poses', row);
      Pose.registerCustom(row);
      await notebook.refresh();
      if (mounted) context.replace('/pose/$id');
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('自定义姿势')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : pick,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(result == null ? '选择单人参考照片' : '重新选照片'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (result case final model?) ...[
          SizedBox(
            height: 260,
            child: PoseImage(
              Pose.fromCustom('preview', '预览', model.svg, model.aspect),
            ),
          ),
          TextField(
            controller: name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '姿势名称'),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('保存姿势'),
          ),
        ],
        for (final p
            in Pose.values.where((p) => p.category == '自定义').toList().reversed)
          ListTile(
            leading: PoseImage(p, width: 36, height: 48),
            title: Text(p.title),
            onTap: () => c.push('/pose/${p.id}'),
          ),
      ],
    ),
  );
}
