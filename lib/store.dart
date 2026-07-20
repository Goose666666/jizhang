import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 本地 JSON 文件持久化的流水存储。
class TxStore extends ChangeNotifier {
  final List<Tx> _txs = [];
  final List<Tx> _trash = []; // 回收站
  bool loaded = false;
  File? _file;

  List<Tx> get all => List.unmodifiable(_txs);
  List<Tx> get trash => List.unmodifiable(_trash);

  File? get _trashFile => _file == null
      ? null
      : File('${_file!.parent.path}${Platform.pathSeparator}jizhang_trash.json');

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}jizhang.json');
    try {
      if (await _file!.exists()) {
        final raw = jsonDecode(await _file!.readAsString()) as List;
        _txs
          ..clear()
          ..addAll(raw.map((e) => Tx.fromJson(e as Map<String, dynamic>)));
        _sort();
      }
      final tf = _trashFile;
      if (tf != null && await tf.exists()) {
        final raw = jsonDecode(await tf.readAsString()) as List;
        _trash
          ..clear()
          ..addAll(raw.map((e) => Tx.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('load failed: $e');
    }
    onboarded = (await _readConfig())['onboarded'] == true;
    loaded = true;
    notifyListeners();
    await importInbox();
  }

  void _sort() => _txs.sort((a, b) => b.date.compareTo(a.date));

  Future<void> _saveTrash() async {
    final tf = _trashFile;
    if (tf == null) return;
    await tf.writeAsString(jsonEncode(_trash.map((t) => t.toJson()).toList()));
  }

  bool onboarded = false; // 是否已完成首次引导

  File? get _configFile => _file == null
      ? null
      : File('${_file!.parent.path}${Platform.pathSeparator}config.json');

  Future<Map<String, dynamic>> _readConfig() async {
    final f = _configFile;
    if (f == null || !await f.exists()) return {};
    try {
      return Map<String, dynamic>.from(
          jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      return {};
    }
  }

  /// 合并写入配置(不覆盖其它字段,原生侧读的 glmKey 不受影响)。
  Future<void> _patchConfig(Map<String, dynamic> patch) async {
    final f = _configFile;
    if (f == null) return;
    final c = await _readConfig()..addAll(patch);
    await f.writeAsString(jsonEncode(c));
  }

  Future<String> readApiKey() async =>
      (await _readConfig())['glmKey'] as String? ?? '';

  Future<void> saveApiKey(String key) => _patchConfig({'glmKey': key.trim()});

  Future<void> setOnboarded() async {
    onboarded = true;
    notifyListeners();
    await _patchConfig({'onboarded': true});
  }

  Future<void> _save() async {
    if (_file == null) return;
    await _file!
        .writeAsString(jsonEncode(_txs.map((t) => t.toJson()).toList()));
  }

  Future<void> add(Tx tx) async {
    _txs.add(tx);
    _sort();
    notifyListeners();
    await _save();
  }

  /// 合并自动记账(AutoAccounting)推送到 inbox.jsonl 的账单。
  /// 返回本次导入的笔数。
  Future<int> importInbox() async {
    if (_file == null) return 0;
    final inbox = File('${_file!.parent.path}${Platform.pathSeparator}inbox.jsonl');
    if (!await inbox.exists()) return 0;
    var count = 0;
    try {
      final lines = await inbox.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          _txs.add(_fromInbox(j));
          count++;
        } catch (e) {
          debugPrint('bad inbox line: $e');
        }
      }
      await inbox.delete();
      if (count > 0) {
        _sort();
        notifyListeners();
        await _save();
      }
    } catch (e) {
      debugPrint('importInbox failed: $e');
    }
    return count;
  }

  Tx _fromInbox(Map<String, dynamic> j) {
    final parent = j['parentCategory'] as String? ?? '';
    final child = j['childCategory'] as String? ?? '';
    final asset = j['asset'] as String? ?? '';
    final isExpense = parent != '收入';

    DateTime date;
    final t = j['time'] as String? ?? '';
    date = DateTime.tryParse(t.replaceFirst(' ', 'T')) ??
        DateTime.fromMillisecondsSinceEpoch(
            (j['receivedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch);

    final account = asset.contains('支付宝') ||
            asset.contains('余额') ||
            asset.contains('花呗')
        ? Account.alipay
        : Account.wechat;

    return Tx(
      id: 'auto_${(j['receivedAt'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch}_${_txs.length}',
      amount: (j['money'] as num).toDouble(),
      isExpense: isExpense,
      account: account,
      category: _mapCategory(isExpense ? '$parent $child' : child, isExpense),
      note: (j['remark'] as String? ?? '').trim(),
      date: date,
    );
  }

  static const _expenseMap = {
    '餐': '吃饭', '食': '吃饭', '外卖': '吃饭', '饮': '吃饭',
    '购': '购物', '淘宝': '购物', '京东': '购物', '超市': '购物',
    '交通': '交通', '打车': '交通', '公交': '交通', '地铁': '交通', '加油': '交通',
    '水电': '水电', '电费': '水电', '话费': '水电',
    '学习': '学习', '书': '学习', '课': '学习',
    '酒店': '酒店', '住宿': '酒店',
    '门票': '门票', '景区': '门票',
    '转账': '转账',
  };
  static const _incomeMap = {
    '工资': '工资', '薪': '工资',
    '红包': '红包',
    '转账': '转账',
    '理财': '理财', '利息': '理财', '收益': '理财',
    '退款': '退款', '退货': '退款',
  };

  String _mapCategory(String raw, bool isExpense) {
    final map = isExpense ? _expenseMap : _incomeMap;
    for (final e in map.entries) {
      if (raw.contains(e.key)) return e.value;
    }
    return '其他';
  }

  /// 批量导入交易,按 id 去重(重复导入同一文件不会记两遍)。
  /// 返回 (新增笔数, 跳过的重复笔数)。
  Future<(int, int)> importTxs(List<Tx> txs) async {
    final existing = _txs.map((t) => t.id).toSet();
    var added = 0, skipped = 0;
    for (final t in txs) {
      if (existing.contains(t.id)) {
        skipped++;
      } else {
        _txs.add(t);
        existing.add(t.id);
        added++;
      }
    }
    if (added > 0) {
      _sort();
      notifyListeners();
      await _save();
    }
    return (added, skipped);
  }

  /// 删除 = 移入回收站(可恢复),最多保留最近 200 条。
  Future<void> remove(String id) async {
    final idx = _txs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final tx = _txs.removeAt(idx);
    _trash.insert(0, tx);
    while (_trash.length > 200) {
      _trash.removeLast();
    }
    notifyListeners();
    await _save();
    await _saveTrash();
  }

  /// 从回收站恢复到账单。
  Future<void> restore(String id) async {
    final idx = _trash.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final tx = _trash.removeAt(idx);
    _txs.add(tx);
    _sort();
    notifyListeners();
    await _save();
    await _saveTrash();
  }

  /// 永久删除回收站里的某条。
  Future<void> purge(String id) async {
    _trash.removeWhere((t) => t.id == id);
    notifyListeners();
    await _saveTrash();
  }

  /// 清空回收站。
  Future<void> emptyTrash() async {
    _trash.clear();
    notifyListeners();
    await _saveTrash();
  }
}
