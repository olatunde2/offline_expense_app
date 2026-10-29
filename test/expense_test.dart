import 'package:flutter_test/flutter_test.dart';
import 'package:offline_expense_app/data/expense.dart';

void main() {
  group('Expense', () {
    test('serializes exact integer cents and UTC timestamp for sync', () {
      final expense = Expense(
        id: 'expense-1',
        amountCents: 1299,
        category: 'Food',
        note: 'Lunch',
        occurredAt: DateTime.utc(2026, 10, 23, 12),
        isSynced: false,
      );

      expect(expense.toJson(), {
        'id': 'expense-1',
        'amount_cents': 1299,
        'category': 'Food',
        'note': 'Lunch',
        'occurred_at': '2026-10-23T12:00:00.000Z',
      });
    });

    test('copyWith changes sync state without changing expense data', () {
      final expense = Expense(
        id: 'expense-1',
        amountCents: 500,
        category: 'Transport',
        note: '',
        occurredAt: DateTime.utc(2026, 1, 1),
        isSynced: false,
      );

      final synced = expense.copyWith(isSynced: true);

      expect(synced.isSynced, isTrue);
      expect(synced.amountCents, expense.amountCents);
      expect(synced.id, expense.id);
    });
  });
}
