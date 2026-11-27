import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const styles = [
  'Golden Hour',
  'Editorial Film',
  'Soft Flash',
  'VHS Camcorder',
  'Vintage',
  'Cinematic',
  'Portrait',
  'Fashion Editorial',
  'Film Photography',
  'Travel Photography',
];
typedef Job = Map<String, dynamic>;

class CloudIssue implements Exception {
  const CloudIssue(this.message);
  final String message;
  @override
  String toString() => message;
}

class StudioService {
  static const endpoint = String.fromEnvironment('PICPIC_AI_URL');
  static const project = String.fromEnvironment('SUPABASE_URL');
  static const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get configured =>
      [endpoint, project].every((v) => Uri.tryParse(v)?.scheme == 'https') &&
      key.isNotEmpty;
  static Future<Supabase>? _init;
  static Future<String>? _session;
  static Future<String> token() async {
    if (!configured) throw const CloudIssue('云端服务尚未配置');
    try {
      final supabase = await (_init ??= Supabase.initialize(
        url: project,
        publishableKey: key,
      ));
      final auth = supabase.client.auth;
      final session = auth.currentSession;
      if (session != null && !session.isExpired) return session.accessToken;
      return (session == null
              ? await auth.signInAnonymously()
              : await auth.refreshSession())
          .session!
          .accessToken;
    } catch (_) {
      _init = null;
      throw const CloudIssue('无法建立创作会话，请检查网络和服务配置');
    }
  }

  Future<http.Response> request(
    String path, {
    Map<String, String>? query,
    Uint8List? data,
    bool post = false,
  }) async {
    final pending = _session ??= token();
    late String jwt;
    try {
      jwt = await pending;
    } finally {
      if (identical(_session, pending)) _session = null;
    }
    final uri = Uri.parse('${endpoint.replaceFirst(RegExp(r'/+$'), '')}$path')
        .replace(queryParameters: query);
    final headers = {'Authorization': 'Bearer $jwt'};
    final response =
        await (post
                ? http.post(uri, headers: headers, body: data)
                : http.get(uri, headers: headers))
            .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = '服务请求失败（${response.statusCode}）';
      try {
        final detail = jsonDecode(utf8.decode(response.bodyBytes))['detail'];
        if (detail is String) message = detail;
      } catch (_) {}
      throw CloudIssue(message);
    }
    return response;
  }

  Future<Job> submit(
    String id,
    String kind,
    String style,
    String prompt,
    Uint8List image,
  ) async => jsonDecode(
    utf8.decode(
      (await request(
        '/jobs/$id',
        query: {'kind': kind, 'style': style, 'prompt': prompt},
        data: image,
        post: true,
      )).bodyBytes,
    ),
  );
  Future<Job> detail(String id) async =>
      jsonDecode(utf8.decode((await request('/jobs/$id')).bodyBytes));
  Future<List<Job>> history() async => List<Job>.from(
    jsonDecode(utf8.decode((await request('/jobs')).bodyBytes)),
  );
  Future<Job> retry(Job job) async => jsonDecode(
    utf8.decode(
      (await request(
        '/jobs/${job['id']}/retry',
        query: {'attempt': '${job['attempt']}'},
        post: true,
      )).bodyBytes,
    ),
  );
  Future<Uint8List> image(String id, String which) async =>
      (await request('/jobs/$id/image/$which')).bodyBytes;
}

String sceneFromLabels(List<String> labels) {
  const groups = {
    '海滩': ['beach', 'seashore', 'seaside', 'coast', 'sandbar'],
    '台阶': ['stairs', 'staircase', 'stairway', 'steps'],
    '墙壁': ['wall', 'brickwork', 'brick wall'],
    '咖啡馆': ['cafe', 'coffee shop', 'cafeteria', 'coffeehouse', 'restaurant'],
    '公园': ['park', 'garden', 'playground', 'lawn'],
    '街道': ['street', 'road', 'sidewalk', 'crosswalk', 'alley'],
    '建筑': [
      'architecture',
      'building',
      'skyscraper',
      'tower',
      'house',
      'arch',
      'facade',
    ],
    '长椅': ['seat', 'bench', 'chair', 'sofa'],
    '镜子': ['mirror'],
    '室内': ['indoor', 'interior', 'room', 'bedroom', 'kitchen', 'living room'],
  };
  for (final label in labels) {
    final words =
        ' ${label.toLowerCase().replaceAll(RegExp('[^a-z]+'), ' ').trim()} ';
    for (final entry in groups.entries) {
      if (entry.value.any((s) => words.contains(' $s '))) return entry.key;
    }
  }
  return '其他';
}
