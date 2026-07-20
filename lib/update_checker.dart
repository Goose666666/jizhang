import 'dart:convert';
import 'dart:io';

/// 当前 App 版本(发新版时和 pubspec 的 version 一起改)。
const kAppVersion = '1.0.0';

/// 版本信息源:通过 CDN 读取仓库根的 version.json。
/// jsDelivr 在国内相对可达,避开直连 api.github.com/raw 需代理的问题;
/// 多个镜像依次尝试,任一成功即可。
const _sources = [
  'https://cdn.jsdelivr.net/gh/Goose666666/jizhang@main/version.json',
  'https://fastly.jsdelivr.net/gh/Goose666666/jizhang@main/version.json',
  'https://gcore.jsdelivr.net/gh/Goose666666/jizhang@main/version.json',
  'https://raw.githubusercontent.com/Goose666666/jizhang/main/version.json',
];

class UpdateInfo {
  final String version;
  final String notes;
  final String downloadUrl;
  UpdateInfo(this.version, this.notes, this.downloadUrl);

  bool get isNewer => _isNewer(version, kAppVersion);
}

class UpdateChecker {
  /// 拉取最新版本信息;全部源失败返回 null(静默,不影响使用)。
  static Future<UpdateInfo?> fetch() async {
    for (final url in _sources) {
      final info = await _tryFetch(url);
      if (info != null) return info;
    }
    return null;
  }

  static Future<UpdateInfo?> _tryFetch(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'jizhang-app');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final v = (j['version'] as String? ?? '').trim();
      if (v.isEmpty) return null;
      return UpdateInfo(
        v,
        (j['notes'] as String? ?? '').trim(),
        (j['downloadUrl'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
  }
}

/// 版本号比较:a 是否比 b 新(语义化,取前三段数字)。
bool _isNewer(String a, String b) {
  final pa = a.replaceAll('v', '').split('.');
  final pb = b.replaceAll('v', '').split('.');
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? int.tryParse(pa[i].trim()) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i].trim()) ?? 0 : 0;
    if (x != y) return x > y;
  }
  return false;
}
