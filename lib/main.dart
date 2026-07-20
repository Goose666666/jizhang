import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_page.dart';
import 'importer.dart';
import 'models.dart';
import 'onboarding_page.dart';
import 'stats_page.dart';
import 'store.dart';
import 'update_checker.dart';

// 水墨墨绿配色
const _brand = Color(0xFF2C5F4F); // 深墨绿(主色)
const _brandDeep = Color(0xFF1F4A3D); // 更深墨绿(渐变尾)
const _ink = Color(0xFF2B2B2B); // 墨色文字
const _paper = Color(0xFFF5F3EE); // 米白纸底
const _expenseColor = Color(0xFFB23A3A); // 朗红
const _incomeColor = Color(0xFF3A7A5A); // 竹绿

void main() {
  runApp(JizhangApp(store: TxStore()..load()));
}

class JizhangApp extends StatelessWidget {
  const JizhangApp({super.key, required this.store});
  final TxStore store;

  ThemeData _theme(Brightness b) {
    final light = b == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: b,
    ).copyWith(
      surface: light ? Colors.white : const Color(0xFF1B1E1C),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'NotoSerifSC',
      scaffoldBackgroundColor: light ? _paper : const Color(0xFF14170F),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: light ? _ink : const Color(0xFFEDEAE1),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
    // 全局套用宋体,正文字色用墨色
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'NotoSerifSC',
        bodyColor: light ? _ink : const Color(0xFFEDEAE1),
        displayColor: light ? _ink : const Color(0xFFEDEAE1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记账',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RootGate(store: store),
    );
  }
}

/// 根据加载状态与是否已引导,决定显示 加载 / 引导 / 主界面。
class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.store});
  final TxStore store;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
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
    if (!widget.store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!widget.store.onboarded) {
      return OnboardingPage(
        store: widget.store,
        onDone: () => setState(() {}),
      );
    }
    return HomePage(store: widget.store);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final TxStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Account? filter; // null = 全部
  late DateTime month; // 当前查看的月份(取每月 1 号)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    widget.store.addListener(_onStore);
    WidgetsBinding.instance.addObserver(this);
    // 启动后静默检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () => _checkUpdate(silent: true));
    });
  }

  Future<void> _checkUpdate({required bool silent}) async {
    final info = await UpdateChecker.fetch();
    if (!mounted) return;
    if (info == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('检查更新失败,请稍后再试'),
            behavior: SnackBarBehavior.floating));
      }
      return;
    }
    if (!info.isNewer) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已是最新版本 v$kAppVersion'),
            behavior: SnackBarBehavior.floating));
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前 v$kAppVersion',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            if (info.notes.isNotEmpty)
              Text(info.notes, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('以后再说')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (info.downloadUrl.isNotEmpty) {
                launchUrl(Uri.parse(info.downloadUrl),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.importInbox().then((n) {
        if (n > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已同步 $n 笔自动记账账单')));
        }
      });
    }
  }

  void _onStore() => setState(() {});

  List<Tx> get _monthTxs => widget.store.all
      .where((t) =>
          t.date.year == month.year &&
          t.date.month == month.month &&
          (filter == null || t.account == filter))
      .toList();

  Future<void> _add() async {
    final tx = await Navigator.push<Tx>(
        context, MaterialPageRoute(builder: (_) => const AddPage()));
    if (tx != null) {
      await widget.store.add(tx);
      if (tx.date.year != month.year || tx.date.month != month.month) {
        setState(() => month = DateTime(tx.date.year, tx.date.month));
      }
    }
  }

  /// 点击一笔进入编辑,保存后按 id 更新。
  Future<void> _editTx(Tx tx) async {
    final updated = await Navigator.push<Tx>(context,
        MaterialPageRoute(builder: (_) => AddPage(edit: tx)));
    if (updated != null) await widget.store.update(updated);
  }

  void _shiftMonth(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));

  static const _pickChannel = MethodChannel('jizhang/filepick');

  Future<void> _importBills() async {
    final Map? picked =
        await _pickChannel.invokeMethod<Map>('pick').catchError((_) => null);
    if (picked == null) return; // 用户取消
    final bytes = picked['bytes'] as Uint8List?;
    final name = picked['name'] as String? ?? '';
    if (bytes == null) return;
    if (!mounted) return;

    void snack(String msg) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

    try {
      final txs = Importer.parse(bytes, name);
      if (txs.isEmpty) {
        snack('未从文件中解析到账单,请确认是微信/支付宝官方流水文件');
        return;
      }
      final (added, skipped) = await widget.store.importTxs(txs);
      // 跳到导入数据最新的月份,方便查看
      if (added > 0) {
        final latest = txs.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
        setState(() => month = DateTime(latest.date.year, latest.date.month));
      }
      snack(added > 0
          ? '导入完成:新增 $added 笔${skipped > 0 ? ",跳过重复 $skipped 笔" : ""}'
          : '没有新账单(该文件 $skipped 笔均已导入过)');
    } catch (e) {
      snack('导入失败:$e');
    }
  }

  Future<void> _openSettings() async {
    final current = await widget.store.readApiKey();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动扫描设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('智谱 GLM API Key',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              '在 bigmodel.cn 注册后创建。填好后开启无障碍权限,支付完停在成功页翻转手机即可自动记账。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'xxxx.xxxx',
                isDense: true,
              ),
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved == true) {
      await widget.store.saveApiKey(ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存,记得开启无障碍权限')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txs = _monthTxs;
    final expense =
        txs.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final income =
        txs.where((t) => !t.isExpense).fold(0.0, (s, t) => s + t.amount);

    // 按天分组
    final Map<String, List<Tx>> byDay = {};
    for (final t in txs) {
      final key =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('记账',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline_rounded),
            tooltip: '统计',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => StatsPage(store: widget.store))),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: '日历',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CalendarPage(store: widget.store))),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入账单',
            onPressed: _importBills,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'trash') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TrashPage(store: widget.store)));
              } else if (v == 'settings') {
                _openSettings();
              } else if (v == 'guide') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => OnboardingPage(
                            store: widget.store,
                            onDone: () => Navigator.pop(context))));
              } else if (v == 'update') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('正在检查更新…'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 1)));
                _checkUpdate(silent: false);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'trash',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 20, color: Theme.of(context).colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Text('回收站${widget.store.trash.isEmpty ? '' : ' (${widget.store.trash.length})'}'),
                ]),
              ),
              const PopupMenuItem(
                value: 'guide',
                child: Row(children: [
                  Icon(Icons.help_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('使用引导'),
                ]),
              ),
              const PopupMenuItem(
                value: 'update',
                child: Row(children: [
                  Icon(Icons.system_update_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('检查更新'),
                ]),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('自动扫描设置'),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !widget.store.loaded
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _SummaryCard(
                      month: month,
                      expense: expense,
                      income: income,
                      onPrev: () => _shiftMonth(-1),
                      onNext: () => _shiftMonth(1),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _FilterBar(
                    value: filter,
                    onChanged: (f) => setState(() => filter = f),
                  ),
                ),
                if (txs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(color: cs.outline),
                  )
                else
                  SliverList.builder(
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final day = days[i];
                      final list = byDay[day]!;
                      return _DayGroup(
                        dayKey: day,
                        txs: list,
                        onTap: _editTx,
                        onDelete: (tx) async {
                          await widget.store.remove(tx.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              content: const Text('已删除'),
                              behavior: SnackBarBehavior.floating,
                              action: SnackBarAction(
                                  label: '撤销',
                                  onPressed: () => widget.store.add(tx)),
                            ));
                        },
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_rounded),
        label: const Text('记一笔', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

String fmtMoney(double v) {
  final s = v.toStringAsFixed(2);
  final trimmed = s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  // 千分位
  final parts = trimmed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return parts.length > 1 ? '${buf.toString()}.${parts[1]}' : buf.toString();
}

/// 渐变 hero 汇总卡
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.month,
    required this.expense,
    required this.income,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final double expense;
  final double income;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final balance = income - expense;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A7A65), _brandDeep],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brandDeep.withValues(alpha: .30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 月份切换
            Row(
              children: [
                _RoundIconBtn(
                    icon: Icons.chevron_left_rounded, onTap: onPrev),
                Expanded(
                  child: Text(
                    '${month.year}年${month.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _RoundIconBtn(
                    icon: Icons.chevron_right_rounded, onTap: onNext),
              ],
            ),
            const SizedBox(height: 14),
            const Text('本月结余',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              '¥${fmtMoney(balance)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                      label: '支出', value: expense, icon: Icons.arrow_upward_rounded),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: Colors.white.withValues(alpha: .22)),
                Expanded(
                  child: _MiniStat(
                      label: '收入',
                      value: income,
                      icon: Icons.arrow_downward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label, required this.value, required this.icon});
  final String label;
  final double value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text('¥${fmtMoney(value)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// 全部 / 微信 / 支付宝 筛选
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final Account? value;
  final ValueChanged<Account?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(Account?, String)>[
      (null, '全部'),
      (Account.wechat, '微信'),
      (Account.alipay, '支付宝'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: items.map((e) {
          final selected = value == e.$1;
          final color = e.$1?.color ?? _brand;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(e.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? color
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  e.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.receipt_long_outlined, size: 56, color: color),
        const SizedBox(height: 12),
        Text('本月还没有记录',
            style: TextStyle(color: color, fontSize: 15)),
        const SizedBox(height: 4),
        Text('点右下角「记一笔」开始',
            style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

/// 一天的流水分组:日期头 + 卡片包裹的流水项
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.dayKey,
    required this.txs,
    required this.onDelete,
    this.onTap,
  });

  final String dayKey;
  final List<Tx> txs;
  final void Function(Tx) onDelete;
  final void Function(Tx)? onTap;

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = DateTime.parse(dayKey);
    final dayExpense =
        txs.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final dayIncome =
        txs.where((t) => !t.isExpense).fold(0.0, (s, t) => s + t.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: Row(
            children: [
              Text(
                '${date.month}月${date.day}日',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
              const SizedBox(width: 6),
              Text(_weekdays[date.weekday - 1],
                  style: TextStyle(fontSize: 12, color: cs.outline)),
              const Spacer(),
              Text(
                [
                  if (dayExpense > 0) '出 ¥${fmtMoney(dayExpense)}',
                  if (dayIncome > 0) '入 ¥${fmtMoney(dayIncome)}',
                ].join('   '),
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < txs.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 64,
                      endIndent: 16,
                      color: cs.outlineVariant.withValues(alpha: .4)),
                _TxTile(tx: txs[i], onDelete: onDelete, onTap: onTap),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.onDelete, this.onTap});
  final Tx tx;
  final void Function(Tx) onDelete;
  final void Function(Tx)? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      if (tx.scene.isNotEmpty) tx.scene,
      if (tx.note.isNotEmpty) tx.category,
      tx.account.label,
    ].join(' · ');

    return Slidable(
      key: ValueKey(tx.id),
      // 左滑露出红色删除按钮,再点击才删除(删除进回收站可恢复)
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(tx),
            backgroundColor: _expenseColor,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: '删除',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(tx),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tx.account.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(categoryIcon(tx.category, tx.isExpense),
                  color: tx.account.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.note.isEmpty ? tx.category : tx.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${tx.isExpense ? '-' : '+'}¥${fmtMoney(tx.amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tx.isExpense ? _expenseColor : _incomeColor,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// 日历页:月历网格 + 选中日期的当天流水(可删除)
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});
  final TxStore store;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime month;
  late DateTime selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selected = DateTime(now.year, now.month, now.day);
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => setState(() {});

  List<Tx> _txOn(DateTime day) => widget.store.all
      .where((t) =>
          t.date.year == day.year &&
          t.date.month == day.month &&
          t.date.day == day.day)
      .toList();

  void _shiftMonth(int d) => setState(() {
        month = DateTime(month.year, month.month + d);
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayTxs = _txOn(selected);
    final dayExpense =
        dayTxs.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final dayIncome =
        dayTxs.where((t) => !t.isExpense).fold(0.0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        children: [
          _CalendarCard(
            month: month,
            selected: selected,
            store: widget.store,
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
            onSelect: (d) => setState(() => selected = d),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Row(
              children: [
                Text(
                  '${selected.month}月${selected.day}日',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  [
                    if (dayExpense > 0) '支出 ¥${fmtMoney(dayExpense)}',
                    if (dayIncome > 0) '收入 ¥${fmtMoney(dayIncome)}',
                    if (dayExpense == 0 && dayIncome == 0) '无记录',
                  ].join('   '),
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
          if (dayTxs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('这天没有记录',
                    style: TextStyle(color: cs.outline, fontSize: 14)),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  for (int i = 0; i < dayTxs.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: .4)),
                    _TxTile(
                      tx: dayTxs[i],
                      onTap: (tx) async {
                        final updated = await Navigator.push<Tx>(context,
                            MaterialPageRoute(
                                builder: (_) => AddPage(edit: tx)));
                        if (updated != null) {
                          await widget.store.update(updated);
                        }
                      },
                      onDelete: (tx) async {
                        await widget.store.remove(tx.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: const Text('已删除'),
                            behavior: SnackBarBehavior.floating,
                            action: SnackBarAction(
                                label: '撤销',
                                onPressed: () => widget.store.add(tx)),
                          ));
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.selected,
    required this.store,
    required this.onPrev,
    required this.onNext,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final TxStore store;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  static const _wk = ['一', '二', '三', '四', '五', '六', '日'];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    // 当月天数与首日星期(周一=1)
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadBlanks = first.weekday - 1; // 前置空格

    // 预统计每天是否有记录
    final hasTx = <int, bool>{};
    for (final t in store.all) {
      if (t.date.year == month.year && t.date.month == month.month) {
        hasTx[t.date.day] = true;
      }
    }

    final cells = <Widget>[];
    for (int i = 0; i < leadBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final isSelected = _sameDay(date, selected);
      final isToday = _sameDay(date, today);
      cells.add(GestureDetector(
        onTap: () => onSelect(date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? _brand : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isToday && !isSelected
                ? Border.all(color: _brand, width: 1.2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isToday ? _brand : cs.onSurface),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasTx[day] == true
                      ? (isSelected ? Colors.white : _brand)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left_rounded)),
              Text('${month.year}年${month.month}月',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded)),
            ],
          ),
          Row(
            children: _wk
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.85,
            children: cells,
          ),
        ],
      ),
    );
  }
}

/// 回收站:已删除的记录,可恢复或永久删除
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.store});
  final TxStore store;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  @override
  void initState() {
    super.initState();
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
    final items = widget.store.trash;
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空回收站?'),
                    content: const Text('清空后将无法恢复这些记录。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: cs.error),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await widget.store.emptyTrash();
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 56, color: cs.outline),
                  const SizedBox(height: 12),
                  Text('回收站是空的',
                      style: TextStyle(color: cs.outline, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('删除的记录会在这里保留,可随时恢复',
                      style: TextStyle(color: cs.outline, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, i) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final tx = items[i];
                return Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tx.account.color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(categoryIcon(tx.category, tx.isExpense),
                            color: tx.account.color, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx.note.isEmpty ? tx.category : tx.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              '${tx.date.month}月${tx.date.day}日 · '
                              '${tx.isExpense ? '-' : '+'}¥${fmtMoney(tx.amount)}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '恢复',
                        icon: Icon(Icons.restore_rounded, color: _brand),
                        onPressed: () async {
                          await widget.store.restore(tx.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(
                                content: Text('已恢复'),
                                behavior: SnackBarBehavior.floating));
                        },
                      ),
                      IconButton(
                        tooltip: '永久删除',
                        icon: Icon(Icons.delete_forever_rounded,
                            color: cs.error),
                        onPressed: () => widget.store.purge(tx.id),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
