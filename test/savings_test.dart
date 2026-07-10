import 'package:flutter_test/flutter_test.dart';
import 'package:yourca/shared/models/models.dart';

void main() {
  group('Savings Utils', () {
    group('MonthlySummary calculations', () {
      test('netSavings is income minus expense', () {
        final summary = MonthlySummary(
          month: DateTime(2026, 7, 1),
          totalIncome: 50000,
          totalExpense: 30000,
          categoryBreakdown: {},
          transactionCount: 10,
        );
        expect(summary.netSavings, 20000);
      });

      test('savingsRate is correct percentage', () {
        final summary = MonthlySummary(
          month: DateTime(2026, 7, 1),
          totalIncome: 50000,
          totalExpense: 35000,
          categoryBreakdown: {},
          transactionCount: 5,
        );
        expect(summary.savingsRate, closeTo(0.30, 0.001));
      });

      test('savingsRate returns 0 when income is 0', () {
        final summary = MonthlySummary(
          month: DateTime(2026, 7, 1),
          totalIncome: 0,
          totalExpense: 5000,
          categoryBreakdown: {},
          transactionCount: 3,
        );
        expect(summary.savingsRate, 0.0);
      });
    });

    group('Transaction model', () {
      test('fromFirestore round-trips correctly', () {
        final original = Transaction(
          id: 'abc123',
          userId: 'user1',
          amount: 499.0,
          type: TransactionType.debit,
          category: 'Food & Dining',
          merchant: 'Swiggy',
          date: DateTime(2026, 7, 10),
          source: TransactionSource.manual,
          createdAt: DateTime(2026, 7, 10, 12),
        );

        final map = original.toFirestore();
        final restored = Transaction.fromFirestore(map, 'abc123');

        expect(restored.id, 'abc123');
        expect(restored.amount, 499.0);
        expect(restored.type, TransactionType.debit);
        expect(restored.merchant, 'Swiggy');
        expect(restored.source, TransactionSource.manual);
      });
    });
  });
}
