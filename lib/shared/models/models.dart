// ─── Transaction Model ─────────────────────────────────────────────────────

enum TransactionType { debit, credit }
enum TransactionSource { sms, manual, statementImport, aa }

class Transaction {
  final String id;
  final String userId;
  final double amount;
  final TransactionType type;
  final String category;
  final String merchant;
  final DateTime date;
  final TransactionSource source;
  final String? rawText;
  final DateTime createdAt;
  final String? note;
  final String? bankReference;

  const Transaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.category,
    required this.merchant,
    required this.date,
    required this.source,
    this.rawText,
    required this.createdAt,
    this.note,
    this.bankReference,
  });

  Transaction copyWith({
    String? id,
    String? userId,
    double? amount,
    TransactionType? type,
    String? category,
    String? merchant,
    DateTime? date,
    TransactionSource? source,
    String? rawText,
    DateTime? createdAt,
    String? note,
    String? bankReference,
  }) {
    return Transaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      merchant: merchant ?? this.merchant,
      date: date ?? this.date,
      source: source ?? this.source,
      rawText: rawText ?? this.rawText,
      createdAt: createdAt ?? this.createdAt,
      note: note ?? this.note,
      bankReference: bankReference ?? this.bankReference,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'amount': amount,
      'type': type.name,
      'category': category,
      'merchant': merchant,
      'date': date.toIso8601String(),
      'source': source.name,
      'raw_text': rawText,
      'created_at': createdAt.toIso8601String(),
      'note': note,
      'bank_reference': bankReference,
    };
  }

  factory Transaction.fromFirestore(Map<String, dynamic> data, String id) {
    return Transaction(
      id: id,
      userId: data['user_id'] ?? '',
      amount: (data['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.debit,
      ),
      category: data['category'] ?? 'Other',
      merchant: data['merchant'] ?? 'Unknown',
      date: DateTime.parse(data['date']),
      source: TransactionSource.values.firstWhere(
        (e) => e.name == (data['source'] ?? 'manual'),
        orElse: () => TransactionSource.manual,
      ),
      rawText: data['raw_text'],
      createdAt: DateTime.parse(data['created_at']),
      note: data['note'],
      bankReference: data['bank_reference'],
    );
  }
}

// ─── User Profile Model ────────────────────────────────────────────────────

class UserProfile {
  final String id;
  final String name;
  final String phoneNumber;
  final DateTime createdAt;
  final double monthlyIncomeSeed;
  final double savingsTargetRate;

  const UserProfile({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.createdAt,
    this.monthlyIncomeSeed = 0,
    this.savingsTargetRate = 0.30,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone_number': phoneNumber,
        'created_at': createdAt.toIso8601String(),
        'monthly_income_seed': monthlyIncomeSeed,
        'savings_target_rate': savingsTargetRate,
      };

  factory UserProfile.fromFirestore(Map<String, dynamic> data, String id) =>
      UserProfile(
        id: id,
        name: data['name'] ?? '',
        phoneNumber: data['phone_number'] ?? '',
        createdAt: DateTime.parse(data['created_at']),
        monthlyIncomeSeed:
            (data['monthly_income_seed'] as num?)?.toDouble() ?? 0,
        savingsTargetRate:
            (data['savings_target_rate'] as num?)?.toDouble() ?? 0.30,
      );

  UserProfile copyWith({
    String? name,
    double? monthlyIncomeSeed,
    double? savingsTargetRate,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber,
      createdAt: createdAt,
      monthlyIncomeSeed: monthlyIncomeSeed ?? this.monthlyIncomeSeed,
      savingsTargetRate: savingsTargetRate ?? this.savingsTargetRate,
    );
  }
}

// ─── Monthly Summary Model ─────────────────────────────────────────────────

class MonthlySummary {
  final DateTime month;
  final double totalIncome;
  final double totalExpense;
  final Map<String, double> categoryBreakdown;
  final int transactionCount;

  const MonthlySummary({
    required this.month,
    required this.totalIncome,
    required this.totalExpense,
    required this.categoryBreakdown,
    required this.transactionCount,
  });

  double get netSavings => totalIncome - totalExpense;
  double get savingsRate =>
      totalIncome == 0 ? 0 : (netSavings / totalIncome).clamp(0.0, 1.0);

  static MonthlySummary empty(DateTime month) => MonthlySummary(
        month: month,
        totalIncome: 0,
        totalExpense: 0,
        categoryBreakdown: {},
        transactionCount: 0,
      );
}

// ─── Savings Suggestion Model ──────────────────────────────────────────────

enum SuggestionType { spike, gap, projection, recurring }

class SavingsSuggestion {
  final SuggestionType type;
  final String title;
  final String description;
  final String? category;
  final double? amount;
  final String emoji;

  const SavingsSuggestion({
    required this.type,
    required this.title,
    required this.description,
    this.category,
    this.amount,
    required this.emoji,
  });
}
