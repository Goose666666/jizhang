import 'package:flutter/material.dart';

/// 账户:微信 / 支付宝
enum Account { wechat, alipay }

extension AccountX on Account {
  String get label => this == Account.wechat ? '微信' : '支付宝';
  Color get color =>
      this == Account.wechat ? const Color(0xFF3E7C5F) : const Color(0xFF3A6B99);
  IconData get icon =>
      this == Account.wechat ? Icons.chat_rounded : Icons.account_balance_wallet_rounded;
}

class Category {
  final String name;
  final IconData icon;
  const Category(this.name, this.icon);
}

/// 支出场景:在学校 / 出去玩
enum Scene { school, travel }

extension SceneX on Scene {
  String get label => this == Scene.school ? '在学校' : '出去玩';
}

/// 每个场景下的支出子类
const schoolCategories = [
  Category('吃饭', Icons.restaurant_rounded),
  Category('交通', Icons.directions_bus_rounded),
  Category('购物', Icons.shopping_bag_rounded),
  Category('转账', Icons.swap_horiz_rounded),
  Category('学习', Icons.menu_book_rounded),
  Category('水电', Icons.bolt_rounded),
  Category('其他', Icons.category_rounded),
];

const travelCategories = [
  Category('吃饭', Icons.restaurant_rounded),
  Category('交通', Icons.directions_bus_rounded),
  Category('购物', Icons.shopping_bag_rounded),
  Category('转账', Icons.swap_horiz_rounded),
  Category('酒店', Icons.hotel_rounded),
  Category('门票', Icons.confirmation_number_rounded),
  Category('其他', Icons.category_rounded),
];

List<Category> sceneCategories(Scene s) =>
    s == Scene.school ? schoolCategories : travelCategories;

const incomeCategories = [
  Category('工资', Icons.payments_rounded),
  Category('红包', Icons.card_giftcard_rounded),
  Category('转账', Icons.swap_horiz_rounded),
  Category('理财', Icons.trending_up_rounded),
  Category('退款', Icons.replay_rounded),
  Category('其他', Icons.category_rounded),
];

/// 全量分类图标表(含新子类 + 旧数据/导入的分类名),用于列表显示。
const _iconByName = <String, IconData>{
  '吃饭': Icons.restaurant_rounded,
  '交通': Icons.directions_bus_rounded,
  '购物': Icons.shopping_bag_rounded,
  '转账': Icons.swap_horiz_rounded,
  '学习': Icons.menu_book_rounded,
  '水电': Icons.bolt_rounded,
  '酒店': Icons.hotel_rounded,
  '门票': Icons.confirmation_number_rounded,
  '工资': Icons.payments_rounded,
  '红包': Icons.card_giftcard_rounded,
  '理财': Icons.trending_up_rounded,
  '退款': Icons.replay_rounded,
  // 兼容旧数据/导入账单的分类名
  '餐饮': Icons.restaurant_rounded,
  '日用': Icons.home_rounded,
  '娱乐': Icons.sports_esports_rounded,
  '医疗': Icons.local_hospital_rounded,
  '其他': Icons.category_rounded,
};

IconData categoryIcon(String name, bool isExpense) =>
    _iconByName[name] ?? Icons.category_rounded;

class Tx {
  final String id;
  final double amount;
  final bool isExpense;
  final Account account;
  final String category;
  final String scene; // 支出场景(在学校/出去玩);收入或旧数据为空
  final String note;
  final DateTime date;

  Tx({
    required this.id,
    required this.amount,
    required this.isExpense,
    required this.account,
    required this.category,
    this.scene = '',
    required this.note,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'isExpense': isExpense,
        'account': account.name,
        'category': category,
        'scene': scene,
        'note': note,
        'date': date.toIso8601String(),
      };

  factory Tx.fromJson(Map<String, dynamic> j) => Tx(
        id: j['id'] as String,
        amount: (j['amount'] as num).toDouble(),
        isExpense: j['isExpense'] as bool,
        account: Account.values.byName(j['account'] as String),
        category: j['category'] as String,
        scene: j['scene'] as String? ?? '',
        note: j['note'] as String? ?? '',
        date: DateTime.parse(j['date'] as String),
      );
}
