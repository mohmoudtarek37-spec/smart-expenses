import 'package:flutter/material.dart';

/// The built-in categories stay available even when a user deletes a custom
/// category. Existing transactions retain their historical category names.
class CategoryCatalog {
  static const expenses = <String>[
    'مشتريات', 'مصاريف شحن', 'اشتراكات', 'كهرباء', 'مياه',
    'مستلزمات بيت', 'مصاريف شخصية', 'أقساط', 'مطاعم', 'صحة',
    'مواصلات', 'فواتير', 'أخرى',
  ];
  static const income = <String>['راتب', 'تحويل وارد', 'إيداع'];

  static const translations = <String, String>{
    'مشتريات': 'Shopping',
    'مصاريف شحن': 'Shipping fees',
    'اشتراكات': 'Subscriptions',
    'كهرباء': 'Electricity',
    'مياه': 'Water',
    'مستلزمات بيت': 'Household',
    'مصاريف شخصية': 'Personal',
    'أقساط': 'Installments',
    'مطاعم': 'Restaurants',
    'صحة': 'Health',
    'مواصلات': 'Transport',
    'فواتير': 'Bills',
    'أخرى': 'Other',
    'راتب': 'Salary',
    'تحويل وارد': 'Incoming transfer',
    'إيداع': 'Deposit',
  };

  static String display(String value, bool english) =>
      english ? (translations[value] ?? value) : value;
}

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({
    super.key,
    required this.isEnglish,
    required this.customCategories,
    required this.onAdd,
    required this.onRemove,
    this.editable = true,
  });

  final bool isEnglish;
  final List<String> Function() customCategories;
  final Future<void> Function() onAdd;
  final Future<void> Function(String) onRemove;
  final bool editable;

  @override
  State<CategoryManagementPage> createState() =>
      _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  bool _busy = false;

  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  Future<void> _add() async {
    if (_busy || !widget.editable) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String category) async {
    if (_busy || !widget.editable) return;
    setState(() => _busy = true);
    try {
      await widget.onRemove(category);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _categoryTile(String category, {bool custom = false}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(custom ? Icons.label_outline : Icons.check_circle_outline,
          color: scheme.primary, size: 21),
      title: Text(CategoryCatalog.display(category, widget.isEnglish),
        style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: custom
          ? IconButton(
              key: ValueKey('delete-category-$category'),
              tooltip: _tr('حذف التصنيف', 'Delete category'),
              onPressed: widget.editable && !_busy
                  ? () => _remove(category) : null,
              icon: Icon(Icons.delete_outline, color: scheme.error),
            )
          : null,
    );
  }

  Widget _group(String title, List<String> names,
      {bool custom = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 9),
        child: Text(title, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          for (var index = 0; index < names.length; index++) ...[
            if (index != 0)
              Divider(height: 1,
                color: scheme.primary.withValues(alpha: 0.12)),
            _categoryTile(names[index], custom: custom),
          ],
          if (names.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(_tr('لسه مفيش تصنيفات مضافة.',
                  'No custom categories yet.'),
                style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.customCategories();
    return Scaffold(
      appBar: AppBar(title: Text(_tr('تخصيص الفئات', 'Manage categories'))),
      body: SafeArea(child: ListView(
        key: const Key('category-management-page'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(_tr(
              'الفئات الأساسية ثابتة، وتقدر تضيف فئات خاصة بيك. '
              'حذف فئة مخصصة مش بيمسح المعاملات القديمة.',
              'Built-in categories are permanent. You can add your own. '
              'Deleting a custom category never erases past transactions.'),
            style: Theme.of(context).textTheme.bodySmall),
          _group(_tr('فئات المصروفات', 'Expense categories'),
              CategoryCatalog.expenses),
          _group(_tr('فئات الإيداع', 'Income categories'),
              CategoryCatalog.income),
          _group(_tr('فئاتك الخاصة', 'Your custom categories'),
              custom, custom: true),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('category-management-add'),
            onPressed: widget.editable && !_busy ? _add : null,
            icon: const Icon(Icons.add),
            label: Text(_tr('إضافة تصنيف جديد', 'Add custom category')),
          ),
          const SizedBox(height: 18),
        ],
      )),
    );
  }
}
