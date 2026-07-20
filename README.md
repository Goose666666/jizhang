# 记账 · jizhang

一个简约大气的跨端记账 App(Android / Windows),用 Flutter 写成。除了手动记账,它的特色是**自动记账**:
支付完停在成功页,**翻转手机**(或下拉点通知),App 用**无障碍服务截屏 + 多模态大模型识别**,把这笔账自动记进你自己的账本 —— 全程本地,数据只存在你的设备上。

> 水墨墨绿配色 + 思源宋体,中式极简风。

## ✨ 功能

- **手动记账**:支出/收入、微信/支付宝账户、场景化分类、备注、日期
- **自动记账(Android)**:翻转手机或点通知 → 截屏 → GLM-4V 识别金额/商户/收支 → 入账
- **账单导入**:直接导入微信(.xlsx)/ 支付宝(.csv,GBK)官方流水文件,自动去重
- **日历视图**:按日查看流水
- **回收站**:删除进回收站可恢复,防误删
- **月度汇总**、微信/支付宝筛选、深色模式
- **本地优先**:所有账单存在设备本地 JSON,不上传任何服务器

## 🧠 自动记账原理

```
翻转手机 / 点通知  →  无障碍服务 takeScreenshot()  →  GLM-4V 多模态识别
   (传感器/通知)         (Android 11+,免 root)           (返回结构化 JSON)
        →  写入本地 inbox  →  Flutter 侧合并入账
```

- **免 root**:用无障碍服务的 `takeScreenshot()`,不需要 Xposed
- **识别**:调用智谱 [GLM-4V-Flash](https://bigmodel.cn)(免费),严格判定"交易成功页 + 有金额"才记账,避免误触记入非账单
- 关键原生代码:`android/app/src/main/kotlin/.../ScanService.kt`(截屏+编排)、`GlmClient.kt`(识别)、`ScanForegroundService.kt`(常驻通知保活)

## 🔑 配置你自己的 API Key(自动记账必需)

本项目**不内置任何 Key**,请用你自己的:

1. 到 [bigmodel.cn](https://bigmodel.cn) 注册,创建一个 API Key(GLM-4V-Flash 免费)
2. 打开 App → 右上角 `⋮` → 自动扫描设置 → 粘贴 Key 保存

## 🚀 构建

需要 Flutter 3.x。

```bash
flutter pub get
flutter run -d windows        # Windows 桌面
flutter build apk --release   # Android 安装包
```

## 📱 Android 自动记账使用步骤

1. 安装后打开 App,`⋮ → 自动扫描设置`填入 GLM API Key
2. 系统设置 → 无障碍 → 开启「记账」服务
3. **国产 ROM(如 MIUI)必做**:把「记账」的**省电策略设为「无限制」+ 开启「自启动」**,否则后台传感器会被系统冻结,翻转失效
4. 支付完停在成功页 → 翻转手机 / 下拉点通知 → 自动记账

## 📥 导入官方账单

- 微信:我 → 服务 → 钱包 → 账单 → 下载账单(用于个人对账),得到 `.xlsx`
- 支付宝:账单 → 开具交易流水证明 / 导出,得到 `.csv`
- App 右上角导入图标 → 选文件,自动解析去重

## 🛠 技术栈

- Flutter + Dart(UI、状态、本地存储)
- 原生 Kotlin(无障碍服务、截屏、传感器、文件选择、GLM HTTP)
- 依赖:`excel`(解析 xlsx)、`gbk_codec`(解码支付宝 GBK)、`flutter_slidable`(左滑删除)、`path_provider`
- 字体:思源宋体 Noto Serif SC(子集化,SIL OFL 1.1)

## ⚠️ 隐私与免责

- 截图仅在识别当下发送给你自己配置的大模型服务(智谱),App 本身不收集、不上传任何数据
- 无障碍权限仅用于截屏识别,代码开源可自查
- 本工具仅供个人记账,请遵守相关 App 的使用条款与当地法律

## 📄 许可

代码 MIT,详见 [LICENSE](LICENSE)。字体 Noto Serif SC 采用 SIL OFL 1.1。
