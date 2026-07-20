import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

const _expenseColor = Color(0xFFB23A3A);
const _incomeColor = Color(0xFF3A7A5A);

// 分类进度条配色(低饱和,和水墨主题协调)
const _palette = [
  Color(0xFF2C5F4F),
  Color(0xFF3A7A5A),
  Color(0xFF6E8B4E),
  Color(0xFF8A6D3B),
  Color(0xFFB4884A),
  Color(0xFF9E7A66),
  Color(0xFF5A7A8A),
  Color(0xFF7A6A9E),
];

String _money(double v) {
  final s = v.toStringAsFixed(2);
  final t = s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  final parts = t.split('.');
  final b = StringBuffer();
  for (int i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) b.write(',');
    b.write(parts[0][i]);
  }
  return parts.length > 1 ? '${b.toString()}.${parts[1]}' : b.toString();
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.store});
  final TxStore store;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late DateTime month;
  bool isExpense = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txs = widget.store.all.where((t) =>
        t.date.year == month.year &&
        t.date.month == month.month &&
        t.isExpense == isExpense);

    // 按分类聚合
    final Map<String, double> byCat = {};
    var total = 0.0;
    for (final t in txs) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
      total += t.amount;
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // 月份切换
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left_rounded)),
              Text('${month.year}年${month.month}月',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              IconButton(
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1)),
                  icon: const Icon(Icons.chevron_right_rounded)),
            ],
          ),
          // 支出/收入切换
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              _seg('支出', true),
              _seg('收入', false),
            ]),
          ),
          const SizedBox(height: 20),
          // 总额
          Center(
            child: Column(
              children: [
                Text(isExpense ? '本月支出' : '本月收入',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('¥${_money(total)}',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: isExpense ? _expenseColor : _incomeColor)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text('本月暂无${isExpense ? '支出' : '收入'}记录',
                      style: TextStyle(color: cs.outline))),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (int i = 0; i < entries.length; i++)
                    _catRow(context, entries[i].key, entries[i].value,
                        total == 0 ? 0 : entries[i].value / total, i),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _seg(String text, bool expense) {
    final selected = isExpense == expense;
    final color = expense ? _expenseColor : _incomeColor;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => isExpense = expense),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : cs.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _catRow(BuildContext context, String name, double amount,
      double ratio, int idx) {
    final cs = Theme.of(context).colorScheme;
    final color = _palette[idx % _palette.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Icon(categoryIcon(name, isExpense), size: 18, color: color),
              const SizedBox(width: 8),
              Text(name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${(ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(width: 10),
              Text('¥${_money(amount)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
