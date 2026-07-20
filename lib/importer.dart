import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:gbk_codec/gbk_codec.dart';

import 'models.dart';

/// 账单导入解析:支持微信(xlsx)和支付宝(GBK csv)官方流水文件。
class Importer {
  /// 根据文件内容自动识别格式并解析成交易列表。
  static List<Tx> parse(Uint8List bytes, String filename) {
    // xlsx 是 zip,头两字节是 'PK'
    final isXlsx = bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (isXlsx || filename.toLowerCase().endsWith('.xlsx')) {
      return _parseWechat(bytes);
    }
    return _parseAlipay(bytes);
  }

  // ---- 微信 xlsx ----
  static List<Tx> _parseWechat(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) return [];
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString().trim() ?? '').toList())
        .toList();
    return _parseRows(rows, Account.wechat);
  }

  // ---- 支付宝 GBK csv ----
  static List<Tx> _parseAlipay(Uint8List bytes) {
    final text = gbk.decode(bytes);
    final rows = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.split(',').map((c) => c.trim()).toList())
        .toList();
    return _parseRows(rows, Account.alipay);
  }

  /// 通用:找到表头行(含"交易时间"),按列名定位,解析数据行。
  static List<Tx> _parseRows(List<List<String>> rows, Account account) {
    int headerIdx = -1;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].any((c) => c == '交易时间')) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) return [];

    final header = rows[headerIdx];
    int col(List<String> names) {
      for (int i = 0; i < header.length; i++) {
        final h = header[i];
        if (names.any((n) => h.contains(n))) return i;
      }
      return -1;
    }

    final cTime = col(['交易时间']);
    final cType = col(['交易类型', '交易分类']);
    final cParty = col(['交易对方']);
    final cGoods = col(['商品']); // 微信"商品" / 支付宝"商品说明"
    final cInOut = col(['收/支']);
    final cAmount = col(['金额']);
    final cOrder = col(['交易单号', '交易订单号']);

    final result = <Tx>[];
    for (int i = headerIdx + 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.length <= cAmount || cTime < 0 || cInOut < 0 || cAmount < 0) {
        continue;
      }
      final inOut = _get(r, cInOut);
      final isExpense = inOut == '支出';
      // 只要支出/收入,跳过"不计收支/中性交易/空"
      if (inOut != '支出' && inOut != '收入') continue;

      final amount = double.tryParse(
          _get(r, cAmount).replaceAll(RegExp(r'[¥￥,\s]'), ''));
      if (amount == null || amount <= 0) continue;

      final date = _parseDate(_get(r, cTime));
      if (date == null) continue;

      final party = _get(r, cParty);
      final goods = _get(r, cGoods);
      final type = _get(r, cType);
      final note = party.isNotEmpty ? party : goods;
      final category = _category(type, goods, party, isExpense);
      final order = _get(r, cOrder);

      result.add(Tx(
        id: order.isNotEmpty
            ? 'imp_$order'
            : 'imp_${account.name}_${date.millisecondsSinceEpoch}_$i',
        amount: double.parse(amount.toStringAsFixed(2)),
        isExpense: isExpense,
        account: account,
        category: category,
        note: note.replaceAll(RegExp(r'^转账备注:'), ''),
        date: date,
      ));
    }
    return result;
  }

  static String _get(List<String> r, int i) =>
      (i >= 0 && i < r.length) ? r[i] : '';

  static DateTime? _parseDate(String s) {
    s = s.trim();
    // "2026-07-19 23:55:00"
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  /// 分类映射:综合交易类型/商品/对方关键词 → app 内分类。
  static String _category(
      String type, String goods, String party, bool isExpense) {
    final text = '$type $goods $party';
    final map = isExpense ? _expenseKw : _incomeKw;
    for (final e in map.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return '其他';
  }

  static const _expenseKw = {
    '餐饮': '餐饮', '美食': '餐饮', '外卖': '餐饮', '零食': '餐饮', '私房菜': '餐饮',
    '牛肉饭': '餐饮', '面': '餐饮',
    '日用': '日用', '百货': '日用', '超市': '日用', '商业': '日用',
    '购物': '购物', '淘宝': '购物', '天猫': '购物', '京东': '购物', '服饰': '购物',
    '交通': '交通', '出行': '交通', '打车': '交通', '地铁': '交通', '公交': '交通',
    '加油': '交通', '火车': '交通', '机票': '交通',
    '娱乐': '娱乐', '文化休闲': '娱乐', '游戏': '娱乐', '电影': '娱乐',
    '会员': '娱乐', '网盘': '娱乐', '视频': '娱乐',
    '医疗': '医疗', '健康': '医疗', '药': '医疗', '医院': '医疗',
    '转账': '转账', '红包': '转账', '群收款': '转账', '存取': '转账', '小荷包': '转账',
  };

  static const _incomeKw = {
    '工资': '工资', '薪': '工资', '报酬': '工资',
    '红包': '红包',
    '转账': '转账', '收款': '转账',
    '退款': '退款', '退货': '退款',
    '理财': '理财', '收益': '理财', '利息': '理财',
  };
}
