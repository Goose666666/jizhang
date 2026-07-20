import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

const _brand = Color(0xFF2C5F4F);
const _expenseColor = Color(0xFFB23A3A);
const _incomeColor = Color(0xFF3A7A5A);

/// 记一笔页面,返回构造好的 [Tx](未入库)。
class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  bool isExpense = true;
  Scene scene = Scene.school;
  Account account = Account.wechat;
  String category = schoolCategories.first.name;
  DateTime date = DateTime.now();
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  List<Category> get _categories =>
      isExpense ? sceneCategories(scene) : incomeCategories;

  Color get _accent => isExpense ? _expenseColor : _incomeColor;

  void _submit() {
    final amount = double.tryParse(amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请输入有效金额'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1)),
      );
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      Tx(
        id: now.microsecondsSinceEpoch.toString(),
        amount: double.parse(amount.toStringAsFixed(2)),
        isExpense: isExpense,
        account: account,
        category: category,
        scene: isExpense ? scene.label : '',
        note: noteCtrl.text.trim(),
        date: DateTime(date.year, date.month, date.day, now.hour, now.minute),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor:
          Theme.of(context).brightness == Brightness.light
              ? const Color(0xFFF5F3EE)
              : const Color(0xFF14170F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('记一笔',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // 收支切换
            _SegToggle(
              isExpense: isExpense,
              onChanged: (v) => setState(() {
                isExpense = v;
                category = _categories.first.name;
              }),
            ),
            const SizedBox(height: 18),
            // 金额输入卡
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('¥',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: _accent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: amountCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d{0,9}\.?\d{0,2}')),
                      ],
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: _accent),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: cs.outlineVariant),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _Label('账户'),
            const SizedBox(height: 10),
            Row(
              children: Account.values.map((a) {
                final selected = account == a;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _Pill(
                    selected: selected,
                    color: a.color,
                    icon: a.icon,
                    label: a.label,
                    onTap: () => setState(() => account = a),
                  ),
                );
              }).toList(),
            ),
            if (isExpense) ...[
              const SizedBox(height: 22),
              _Label('场景'),
              const SizedBox(height: 10),
              Row(
                children: Scene.values.map((s) {
                  final selected = scene == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _Pill(
                      selected: selected,
                      color: _brand,
                      icon: s == Scene.school
                          ? Icons.school_rounded
                          : Icons.beach_access_rounded,
                      label: s.label,
                      onTap: () => setState(() {
                        scene = s;
                        category = _categories.first.name;
                      }),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 22),
            _Label('分类'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.map((c) {
                final selected = category == c.name;
                return _Pill(
                  selected: selected,
                  color: _brand,
                  icon: c.icon,
                  label: c.name,
                  onTap: () => setState(() => category = c.name),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            _Label('备注与日期'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        hintText: '添加备注(可选)',
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      maxLength: 40,
                    ),
                  ),
                  Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: cs.outlineVariant.withValues(alpha: .4)),
                  ListTile(
                    leading: Icon(Icons.event_outlined, color: cs.onSurfaceVariant),
                    title: Text('${date.year}年${date.month}月${date.day}日'),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.outline),
                    onTap: _pickDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('保存',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

/// 支出 / 收入 切换
class _SegToggle extends StatelessWidget {
  const _SegToggle({required this.isExpense, required this.onChanged});
  final bool isExpense;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String text, bool expense) {
      final selected = isExpense == expense;
      final color = expense ? _expenseColor : _incomeColor;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(expense),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : cs.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [seg('支出', true), seg('收入', false)]),
    );
  }
}

/// 通用选择 pill(账户/分类)
class _Pill extends StatelessWidget {
  const _Pill({
    required this.selected,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : cs.outlineVariant.withValues(alpha: .5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17, color: selected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : cs.onSurface)),
          ],
        ),
      ),
    );
  }
}
