import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/expense.dart';
import '../state/expense_controller.dart';

const _categories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Health',
  'Other',
];

final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final _date = DateFormat('MMM d');

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expenseControllerProvider);
    final controller = ref.read(expenseControllerProvider.notifier);
    final total = state.expenses.fold<int>(
      0,
      (sum, expense) => sum + expense.amountCents,
    );
    final monthTotal = state.expenses
        .where(
          (expense) =>
              expense.occurredAt.year == DateTime.now().year &&
              expense.occurredAt.month == DateTime.now().month,
        )
        .fold<int>(0, (sum, expense) => sum + expense.amountCents);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pocket Ledger',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'YOUR MONEY, YOUR WAY',
              style: TextStyle(fontSize: 10, letterSpacing: 1.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sync settings',
            onPressed: () =>
                _showSyncSettings(context, ref, state.syncEndpoint),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.syncNow,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              _SyncStatusCard(
                syncing: state.syncing,
                pendingCount: state.pendingCount,
                endpointConfigured: state.syncEndpoint != null,
                onSync: controller.syncNow,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: state.error!),
              ],
              const SizedBox(height: 18),
              _SummaryCard(monthTotal: monthTotal, total: total),
              const SizedBox(height: 18),
              _SectionHeader(
                title: 'Spending this week',
                trailing: Text(
                  _money.format(total / 100),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              _WeeklyChart(expenses: state.expenses),
              const SizedBox(height: 22),
              _SectionHeader(
                title: 'Recent expenses',
                trailing: Text(
                  '${state.expenses.length} entries',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              if (state.expenses.isEmpty)
                const _EmptyExpenses()
              else
                ...state.expenses
                    .take(30)
                    .map(
                      (expense) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _ExpenseTile(
                          expense: expense,
                          onDelete: () => _confirmDelete(context, ref, expense),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpense(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
    );
  }

  Future<void> _showAddExpense(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var category = _categories.first;
    var occurredAt = DateTime.now();
    final expense = await showModalBottomSheet<ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New expense',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: r'$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setSheetState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: occurredAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setSheetState(() => occurredAt = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      'Date: ${DateFormat.yMMMd().format(occurredAt)}',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      final cents = _amountToCents(amountController.text);
                      Navigator.pop(
                        context,
                        ExpenseDraft(
                          cents,
                          category,
                          noteController.text,
                          occurredAt,
                        ),
                      );
                    },
                    child: const Text('Save on this device'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
    if (expense == null) return;
    await ref
        .read(expenseControllerProvider.notifier)
        .addExpense(
          amountCents: expense.amountCents,
          category: expense.category,
          note: expense.note,
          occurredAt: expense.occurredAt,
        );
  }

  String? _validateAmount(String? value) {
    if (value == null || !_amountPattern.hasMatch(value.trim())) {
      return 'Enter a positive amount with up to two decimal places';
    }
    final cents = _amountToCents(value);
    if (cents <= 0 || cents > 999999999999) {
      return 'Amount is outside the supported range';
    }
    return null;
  }

  Future<void> _showSyncSettings(
    BuildContext context,
    WidgetRef ref,
    String? endpoint,
  ) async {
    final textController = TextEditingController(text: endpoint ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync server'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://api.example.com',
            helperText: 'Uses POST /expenses/sync',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      try {
        await ref
            .read(expenseControllerProvider.notifier)
            .setSyncEndpoint(textController.text);
      } on FormatException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    }
    textController.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This change will sync when you are online.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expenseControllerProvider.notifier).deleteExpense(expense);
    }
  }
}

final _amountPattern = RegExp(r'^\d{1,10}(?:\.\d{1,2})?$');

int _amountToCents(String input) {
  final parts = input.trim().split('.');
  final whole = int.parse(parts[0]);
  final fractional = parts.length == 1 ? '' : parts[1].padRight(2, '0');
  return whole * 100 + (fractional.isEmpty ? 0 : int.parse(fractional));
}

class ExpenseDraft {
  const ExpenseDraft(
    this.amountCents,
    this.category,
    this.note,
    this.occurredAt,
  );

  final int amountCents;
  final String category;
  final String note;
  final DateTime occurredAt;
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.syncing,
    required this.pendingCount,
    required this.endpointConfigured,
    required this.onSync,
  });

  final bool syncing;
  final int pendingCount;
  final bool endpointConfigured;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final color = pendingCount == 0
        ? const Color(0xFF176B54)
        : const Color(0xFF9A6500);
    final label = !endpointConfigured
        ? 'Saved offline · add a sync server'
        : syncing
        ? 'Syncing your changes'
        : pendingCount == 0
        ? 'All changes synced'
        : '$pendingCount change${pendingCount == 1 ? '' : 's'} waiting to sync';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              endpointConfigured
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (endpointConfigured && pendingCount > 0)
              IconButton(
                tooltip: 'Sync now',
                onPressed: syncing ? null : () => onSync(),
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.monthTotal, required this.total});

  final int monthTotal;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF123F35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SPENT THIS MONTH',
            style: TextStyle(color: Colors.white70, letterSpacing: 1.3),
          ),
          const SizedBox(height: 7),
          Text(
            _money.format(monthTotal / 100),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFA5D8BF),
                size: 17,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Encrypted on this device',
                  style: TextStyle(color: Color(0xFFD4E9DF), fontSize: 12),
                ),
              ),
              Text(
                'Lifetime ${_money.format(total / 100)}',
                style: const TextStyle(color: Color(0xFFD4E9DF), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final dailyTotals = List<int>.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return expenses
          .where((expense) => DateUtils.isSameDay(expense.occurredAt, date))
          .fold<int>(0, (sum, expense) => sum + expense.amountCents);
    });
    final peak = dailyTotals.fold<int>(
      0,
      (value, item) => item > value ? item : value,
    );
    final maxY = peak == 0 ? 1000.0 : peak * 1.25;
    return SizedBox(
      height: 168,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 16, 8),
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index > 6) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _date.format(
                            today.subtract(Duration(days: 6 - index)),
                          ),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List<BarChartGroupData>.generate(
                dailyTotals.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: dailyTotals[index].toDouble(),
                      width: 18,
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFF4AA98A),
                    ),
                  ],
                ),
              ),
            ),
            duration: const Duration(milliseconds: 220),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      trailing,
    ],
  );
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.onDelete});

  final Expense expense;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE5F2EC),
        child: Icon(
          _categoryIcon(expense.category),
          color: const Color(0xFF176B54),
        ),
      ),
      title: Text(expense.note.isEmpty ? expense.category : expense.note),
      subtitle: Text(
        '${expense.category} · ${_date.format(expense.occurredAt)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '-${_money.format(expense.amountCents / 100)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Icon(
                expense.isSynced
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                size: 14,
                color: expense.isSynced ? Colors.green : Colors.orange.shade800,
              ),
            ],
          ),
          IconButton(
            tooltip: 'Delete expense',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    ),
  );
}

IconData _categoryIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_rounded,
  'Transport' => Icons.directions_car_rounded,
  'Shopping' => Icons.shopping_bag_rounded,
  'Bills' => Icons.receipt_long_rounded,
  'Health' => Icons.favorite_border_rounded,
  _ => Icons.payments_outlined,
};

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 42,
            color: Color(0xFF176B54),
          ),
          const SizedBox(height: 10),
          Text(
            'A clear picture starts here',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Add your first expense. It is saved securely on this device, even offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF0EA),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_outlined, color: Color(0xFFA33D1F)),
          const SizedBox(width: 8),
          Expanded(child: Text('Sync paused: $message')),
        ],
      ),
    ),
  );
}
