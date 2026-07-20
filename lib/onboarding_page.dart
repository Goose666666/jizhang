import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';

const _brand = Color(0xFF2C5F4F);
const _brandDeep = Color(0xFF1F4A3D);

/// 首次启动引导:欢迎 → 填 API Key → 开无障碍 → 设省电 → 完成。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.store, required this.onDone});
  final TxStore store;
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('jizhang/filepick');
  final _pageCtrl = PageController();
  final _keyCtrl = TextEditingController();
  int _page = 0;
  bool _accessibilityOn = false;

  bool get _android => Platform.isAndroid;

  late final List<_Step> _steps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _steps = [
      const _Step.welcome(),
      const _Step.apiKey(),
      if (_android) const _Step.accessibility(),
      if (_android) const _Step.battery(),
    ];
    _loadKey();
  }

  Future<void> _loadKey() async {
    // 引导页不预填任何 Key,保持空白,由使用者自己填入
    _refreshAccessibility();
  }

  /// 仅在用户实际填了内容时才保存,避免空输入覆盖掉已有的 Key。
  Future<void> _maybeSaveKey() async {
    final k = _keyCtrl.text.trim();
    if (k.isNotEmpty) await widget.store.saveApiKey(k);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAccessibility();
  }

  Future<void> _refreshAccessibility() async {
    if (!_android) return;
    try {
      final on = await _channel.invokeMethod<bool>('isAccessibilityOn') ?? false;
      if (mounted) setState(() => _accessibilityOn = on);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    // 离开 API Key 页时保存(仅在填了内容时)
    if (_steps[_page].kind == _Kind.apiKey) {
      await _maybeSaveKey();
    }
    if (_page == _steps.length - 1) {
      await widget.store.setOnboarded();
      widget.onDone();
      return;
    }
    _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    await _maybeSaveKey();
    await widget.store.setOnboarded();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _steps.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部:跳过
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('跳过', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _buildStep(_steps[i]),
              ),
            ),
            // 圆点指示
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? _brand : _brand.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(last ? '开始记账' : '下一步',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(_Step s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF12C56B), _brandDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(s.icon, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 24),
          Text(s.title,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF2B2B2B))),
          const SizedBox(height: 12),
          Text(s.desc,
              style: const TextStyle(
                  fontSize: 15, height: 1.6, color: Color(0xFF5A5A5A))),
          const SizedBox(height: 24),
          if (s.kind == _Kind.apiKey) _apiKeyField(),
          if (s.kind == _Kind.accessibility) _accessibilityAction(),
          if (s.kind == _Kind.battery) _batteryAction(),
        ],
      ),
    );
  }

  Widget _apiKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _keyCtrl,
          decoration: InputDecoration(
            hintText: '粘贴智谱 GLM API Key',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: 8),
        const Text('到 bigmodel.cn 免费注册后创建。不填也能用手动记账,只是没有自动扫描。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _accessibilityAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _accessibilityOn
                ? const Color(0xFF3A7A5A).withValues(alpha: .12)
                : Colors.orange.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(_accessibilityOn ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: _accessibilityOn ? const Color(0xFF3A7A5A) : Colors.orange,
                  size: 20),
              const SizedBox(width: 8),
              Text(_accessibilityOn ? '无障碍已开启' : '无障碍未开启',
                  style: TextStyle(
                      color: _accessibilityOn
                          ? const Color(0xFF3A7A5A)
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _channel.invokeMethod('openAccessibility'),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            side: const BorderSide(color: _brand),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          label: const Text('去开启无障碍'),
        ),
      ],
    );
  }

  Widget _batteryAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () => _channel.invokeMethod('openAppDetails'),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            side: const BorderSide(color: _brand),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          label: const Text('去应用设置'),
        ),
      ],
    );
  }
}

enum _Kind { welcome, apiKey, accessibility, battery }

class _Step {
  final _Kind kind;
  final IconData icon;
  final String title;
  final String desc;

  const _Step(this.kind, this.icon, this.title, this.desc);

  const _Step.welcome()
      : this(_Kind.welcome, Icons.menu_book_rounded, '欢迎使用记账',
            '简约的记账 App。支持手动记账、导入微信/支付宝账单,以及支付后翻转手机自动记账。所有数据只存在你的手机本地。');
  const _Step.apiKey()
      : this(_Kind.apiKey, Icons.vpn_key_rounded, '配置识别 Key',
            '自动记账用智谱 GLM-4V 大模型识别支付截图,需要你自己的 API Key(免费)。');
  const _Step.accessibility()
      : this(_Kind.accessibility, Icons.accessibility_new_rounded, '开启无障碍',
            '自动记账需要无障碍权限来截取当前支付页面(仅本地识别,不上传)。请在设置里找到「记账」并开启。');
  const _Step.battery()
      : this(_Kind.battery, Icons.battery_charging_full_rounded, '允许后台运行',
            '国产手机(如小米/MIUI)会冻结后台。请在应用设置里把「省电策略」设为「无限制」,并开启「自启动」,否则翻转手机可能失灵。');
}
