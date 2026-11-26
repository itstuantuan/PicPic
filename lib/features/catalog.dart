import 'dart:convert';

import 'pose_vision.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Pose {
  const Pose(
    this.id,
    this.category,
    this.title,
    this.asset,
    this.aspectRatio,
    this.heightFraction,
    this.steps, {
    this.people = 1,
    this.svg,
  });
  final String id, category, title, asset;
  final int people;
  final double aspectRatio, heightFraction;
  final List<String> steps;
  final String? svg;
  static final rigs = <String, Rig>{};
  static Pose fromCustom(String id, String name, String svg, double aspect) =>
      Pose(id, '自定义', name, '', aspect, .62, [
        '观察身体朝向',
        '调整双手和重心',
        '对照轮廓微调姿势',
      ], svg: svg);
  static void registerCustom(Map<String, Object?> row) {
    final id = row['id'] as String;
    final rig = decodeRig(jsonDecode(row['rig'] as String));
    rigs[id] = rig;
    values.removeWhere((p) => p.id == id);
    values.add(
      fromCustom(
        id,
        row['name'] as String,
        row['svg'] as String,
        (row['aspect'] as num).toDouble(),
      ),
    );
  }

  String get tip => steps.first;
  String get scene => switch (category) {
    '坐姿' => '长椅 · 台阶',
    '旅行' || '背影' => '公园 · 海滩',
    '自拍' || '人像' => '镜子 · 室内',
    '情侣' || '双人' => '街道 · 公园',
    _ => '街道 · 建筑',
  };
  String get difficulty => people == 2
      ? '配合练习'
      : (title.contains('抬膝') || title.contains('后踢腿') ? '进阶' : '入门');
  String get advice => people == 2
      ? '横向留出两人的间距，让两个人的四肢都入框。'
      : (category == '自拍'
            ? '手机略高于视线，给手臂留出空间。'
            : category == '坐姿'
            ? '从侧前方取景，给膝盖和脚尖留出空间。'
            : '镜头保持平稳，先让双脚完整进入画面。');

  static const crouch = Pose(
    'crouch',
    '坐姿',
    '蹲姿托腮',
    'assets/crouch.png',
    498 / 756,
    .43,
    ['手肘搭在膝盖上，轻轻托腮', '重心放低，让双膝自然分开', '侧过脸，视线朝向镜头'],
  );
  static const stand = Pose(
    'stand',
    '站姿',
    '侧身扶头',
    'assets/stand.png',
    418 / 1012,
    .60,
    ['单手扶住后脑，另一只手轻搭腰间', '身体稍微侧向镜头', '放松肩膀，把重心移到一条腿上'],
  );
  static const lookBack = Pose(
    'lookBack',
    '背影',
    '回眸',
    'assets/poses/01-回眸.png',
    806 / 1952,
    .60,
    ['背向镜头，双脚前后错开', '从肩膀上方回头看镜头', '手臂自然垂下'],
  );
  static const shade = Pose(
    'shade',
    '人像',
    '遮阳',
    'assets/poses/02-遮阳.png',
    810 / 1940,
    .60,
    ['一只手抬到眉毛上方', '手掌微弯，像在挡阳光', '另一只手放松垂下'],
  );
  static const walk = Pose(
    'walk',
    '行走',
    '迈步',
    'assets/poses/03-迈步.png',
    806 / 1952,
    .60,
    ['朝镜头斜前方迈出一步', '让后脚跟自然抬起', '双臂随步伐轻摆'],
  );
  static const fold = Pose(
    'fold',
    '人像',
    '交叉抱臂',
    'assets/poses/04-交叉抱臂.png',
    807 / 1949,
    .60,
    ['身体稍微转向一侧', '两臂在胸前轻轻交叠', '肩膀放松，双脚分开'],
  );
  static const wave = Pose(
    'wave',
    '街拍',
    '踮脚挥手',
    'assets/poses/05-踮脚挥手.png',
    806 / 1952,
    .60,
    ['侧身站好，后脚轻轻踮起', '一只手抬到肩旁挥手', '另一只手搭在腰间'],
  );
  static const crossLegs = Pose(
    'crossLegs',
    '坐姿',
    '盘腿坐',
    'assets/poses/06-盘腿坐.png',
    1130 / 1392,
    .45,
    ['面向镜头盘腿坐下', '双手轻放在两膝上', '挺直身体，放松肩膀'],
  );
  static const sideSit = Pose(
    'sideSit',
    '坐姿',
    '侧坐撑地',
    'assets/poses/07-侧坐撑地.png',
    1594 / 987,
    .40,
    ['坐下，把双腿收向同一侧', '身后一只手轻轻撑地', '另一只手搭在腿上'],
  );
  static const kneel = Pose(
    'kneel',
    '街拍',
    '单膝跪姿',
    'assets/poses/08-单膝跪姿.png',
    1056 / 1490,
    .48,
    ['单膝跪地，另一只脚踩稳', '前臂搭在抬起的膝盖上', '上身略向镜头侧转'],
  );
  static const stretch = Pose(
    'stretch',
    '旅行',
    '伸展',
    'assets/poses/09-伸展.png',
    806 / 1952,
    .65,
    ['双手举过头顶，轻轻相握', '上身向一侧舒展', '双脚踩稳，保持平衡'],
  );
  static const lean = Pose(
    'lean',
    '人像',
    '背手前倾',
    'assets/poses/10-背手前倾.png',
    806 / 1952,
    .54,
    ['侧身站立，双手在背后相握', '从髋部轻轻向前倾', '抬起下巴，放松双肩'],
  );
  static const anns01 = Pose(
    'anns01',
    '街拍',
    '前伸点地',
    'assets/poses/anns-01.png',
    1080 / 1457,
    .60,
    ['将重心放在后脚', '另一只脚朝镜头前方伸出', '双手在胸前轻握杯子'],
  );
  static const anns02 = Pose(
    'anns02',
    '站姿',
    '交叉站立',
    'assets/poses/anns-02.png',
    1024 / 1536,
    .60,
    ['把一只脚交叉放在另一只脚前', '一手抬起扶住后脑', '另一只手自然落在身侧'],
  );
  static const anns03 = Pose(
    'anns03',
    '站姿',
    '斜站展臂',
    'assets/poses/anns-03.png',
    1086 / 1449,
    .60,
    ['身体稍微转侧，双脚前后站', '两肘微弯，双手向外展开', '轻轻低头看向前脚'],
  );
  static const anns04 = Pose(
    'anns04',
    '行走',
    '街头跨步',
    'assets/poses/anns-04.png',
    1085 / 1449,
    .60,
    ['侧身向前迈一大步', '让两脚在画面里自然分开', '转头朝镜头看'],
  );
  static const anns05 = Pose(
    'anns05',
    '街拍',
    '靠墙轻倚',
    'assets/poses/anns-05.png',
    1024 / 1536,
    .60,
    ['靠近墙面，肩背轻倚', '双腿一前一后轻轻交错', '双手放松落到身侧'],
  );
  static const anns06 = Pose(
    'anns06',
    '背影',
    '栏边抬手回望',
    'assets/poses/anns-06.png',
    1087 / 1447,
    .60,
    ['侧身站在栏边，双脚靠近', '抬起一只手放在额前', '轻轻回头，让视线落在镜头旁'],
  );
  static const anns07 = Pose(
    'anns07',
    '坐姿',
    '坐姿单腿前伸',
    'assets/poses/anns-07.png',
    1086 / 1448,
    .48,
    ['坐在长椅边，侧身对着镜头', '一脚向前伸，另一腿弯曲', '一手撑在身侧，另一手靠近后颈'],
  );
  static const anns08 = Pose(
    'anns08',
    '坐姿',
    '斜坐叠膝',
    'assets/poses/anns-08.png',
    1024 / 1536,
    .48,
    ['在座位边缘坐稳，身体略微转侧', '把一条腿轻轻叠在另一条腿上', '双手自然搭在膝盖上'],
  );
  static const anns09 = Pose(
    'anns09',
    '坐姿',
    '交错垂腿',
    'assets/poses/anns-09.png',
    1094 / 1437,
    .48,
    ['坐在矮台边，双脚放松', '让两腿交错，一只脚斜向外伸', '上身略微转侧，视线看向旁边'],
  );
  static const anns10 = Pose(
    'anns10',
    '坐姿',
    '台阶前倾',
    'assets/poses/anns-10.png',
    1024 / 1536,
    .48,
    ['坐在台阶边，双膝靠近', '从髋部往前倾，双臂放松', '轻轻歪头，看向镜头'],
  );
  static const anns11 = Pose(
    'anns11',
    '坐姿',
    '屈膝捧杯',
    'assets/poses/anns-11.png',
    1024 / 1536,
    .48,
    ['在座面上屈膝坐好', '一手拿杯，另一只手轻触额前', '放松肩膀，脸朝镜头'],
  );
  static const anns12 = Pose(
    'anns12',
    '坐姿',
    '台阶错层坐',
    'assets/poses/anns-12.png',
    1086 / 1448,
    .48,
    ['侧坐在台阶边缘，一只脚踩高一级', '另一条腿斜向前伸，脚踩低一级', '一手轻托脸侧，另一手在身旁撑稳'],
  );

  static final values = <Pose>[
    crouch,
    stand,
    lookBack,
    shade,
    walk,
    fold,
    wave,
    crossLegs,
    sideSit,
    kneel,
    stretch,
    lean,
    anns01,
    anns02,
    anns03,
    anns04,
    anns05,
    anns06,
    anns07,
    anns08,
    anns09,
    anns10,
    anns11,
    anns12,
  ];
  static Future<void> load() async {
    final legacy = jsonDecode(
      await rootBundle.loadString('assets/studies/reference_rigs.json'),
    ) as Map<String, dynamic>;
    for (final e in legacy.entries) {
      rigs[e.key] = decodeRig(e.value);
    }
    final data = jsonDecode(
      await rootBundle.loadString('assets/studies/landmarks.json'),
    ) as Map<String, dynamic>;
    final studies = data.entries.map((e) {
      final p = e.value;
      if (p['people'] == 1) {
        // The illustrated templates label sides as seen by the photographer.
        rigs[e.key] = decodeRig(p['joints'][0]).map(
          (k, v) => MapEntry(
            k.startsWith('l')
                ? 'r${k.substring(1)}'
                : k.startsWith('r')
                ? 'l${k.substring(1)}'
                : k,
            v,
          ),
        );
      }
      return Pose(
        e.key,
        p['category'],
        p['title'],
        'assets/studies/${e.key}.svg',
        (p['aspect'] as num).toDouble(),
        .58,
        List<String>.from(p['steps']),
        people: p['people'],
      );
    }).toList();
    values.removeWhere((p) => p.asset.endsWith('.svg'));
    values.addAll(studies);
  }

  static Pose? find(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class PoseImage extends StatelessWidget {
  const PoseImage(
    this.pose, {
    super.key,
    this.height,
    this.width,
    this.thumbnail = false,
  });
  final Pose pose;
  final double? height, width;
  final bool thumbnail;
  @override
  Widget build(BuildContext context) => pose.svg != null
      ? SvgPicture.string(
          pose.svg!,
          height: height,
          width: width,
          fit: BoxFit.contain,
        )
      : pose.asset.endsWith('.svg')
      ? SvgPicture.asset(
          pose.asset,
          fit: BoxFit.contain,
          height: height,
          width: width,
        )
      : Image.asset(
          pose.asset,
          fit: BoxFit.contain,
          height: height,
          width: width,
          cacheWidth: thumbnail ? 180 : null,
        );
}
