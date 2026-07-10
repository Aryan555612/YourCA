// ──────────────────────────────────────────────────────────────────────────────
// Android SMS Bank Parser
// Platform: Android only — guarded by Platform.isAndroid checks at call sites.
//
// NOTE: SMS-based transaction reading works because this app is sideloaded
// (not distributed via Play Store). The app transparently requests
// READ_SMS / RECEIVE_SMS at runtime, only after explaining why.
// ──────────────────────────────────────────────────────────────────────────────

/// Parsed result from a bank SMS.
class SmsParseResult {
  final double amount;
  final bool isDebit;
  final String merchant;
  final String? reference;
  final DateTime? date;
  final String bank;

  const SmsParseResult({
    required this.amount,
    required this.isDebit,
    required this.merchant,
    this.reference,
    this.date,
    required this.bank,
  });
}

class BankSmsParser {
  BankSmsParser._();
  static final BankSmsParser instance = BankSmsParser._();

  // ── Sender ID → Bank name mapping ──────────────────────────────────────
  static const Map<String, String> _senderBankMap = {
    'SBIINB': 'SBI',
    'SBIATM': 'SBI',
    'SBI-': 'SBI',
    'HDFCBK': 'HDFC',
    'HDFC-': 'HDFC',
    'ICICIB': 'ICICI',
    'ICICI-': 'ICICI',
    'AXISBK': 'Axis',
    'AXISBN': 'Axis',
    'KOTAKB': 'Kotak',
    'KOTAK-': 'Kotak',
    'PNBSMS': 'PNB',
    'PNB---': 'PNB',
    'INDBNK': 'IndusInd',
    'YESBNK': 'Yes Bank',
    'IDFCBK': 'IDFC First',
    'SCBANK': 'Standard Chartered',
    'PAYTMB': 'Paytm Payments Bank',
  };

  // ── Amount regex patterns ───────────────────────────────────────────────
  static final _amountPatterns = [
    RegExp(r'(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'([\d,]+\.?\d*)\s*(?:INR|Rs\.?)', caseSensitive: false),
  ];

  // ── Debit keywords ──────────────────────────────────────────────────────
  static final _debitPattern = RegExp(
    r'\b(?:debited|debit|withdrawn|withdrawal|spent|paid|payment|purchase|dr\.?)\b',
    caseSensitive: false,
  );

  // ── Credit keywords ─────────────────────────────────────────────────────
  static final _creditPattern = RegExp(
    r'\b(?:credited|credit|received|deposited|cr\.?)\b',
    caseSensitive: false,
  );

  // ── Merchant/UPI patterns ───────────────────────────────────────────────
  static final _merchantPatterns = [
    RegExp(r'(?:at|to|from|by|merchant|payee)[:\s]+([A-Za-z0-9\s\.\-\_]+?)(?:\s+on|\s+ref|\s+via|\s*\.|\s*,|$)',
        caseSensitive: false),
    RegExp(r'VPA\s+([A-Za-z0-9@\.\-\_]+)', caseSensitive: false),
    RegExp(r'UPI[:\s]+([A-Za-z0-9@\.\-\_]+)', caseSensitive: false),
    RegExp(r'trf to\s+([A-Za-z\s]+?)(?:\s+ref|\s+on|\s*\.)', caseSensitive: false),
  ];

  // ── Reference number patterns ───────────────────────────────────────────
  static final _refPattern = RegExp(
    r'(?:ref(?:erence)?[.\s]*(?:no\.?)?|txn\s*(?:id)?|utr)[:\s]*([A-Z0-9]+)',
    caseSensitive: false,
  );

  // ── Date patterns ───────────────────────────────────────────────────────
  static final _datePatterns = [
    RegExp(r'(\d{2})[/-](\d{2})[/-](\d{4})'),
    RegExp(r'(\d{2})-([A-Za-z]{3})-(\d{4})'),
    RegExp(r'(\d{2})[/-](\d{2})[/-](\d{2})'),
  ];

  // ── Month abbreviation → number ─────────────────────────────────────────
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  // ── Public parse method ─────────────────────────────────────────────────
  /// Attempts to parse a bank SMS.
  /// Returns null if the SMS does not appear to be a bank transaction alert.
  SmsParseResult? parse({
    required String body,
    required String sender,
  }) {
    final bank = _identifyBank(sender, body);
    if (bank == null) return null;

    final amount = _extractAmount(body);
    if (amount == null) return null;

    final isDebit = _debitPattern.hasMatch(body);
    final isCredit = _creditPattern.hasMatch(body);

    // Skip if neither debit nor credit keyword found
    if (!isDebit && !isCredit) return null;

    final merchant = _extractMerchant(body);
    final reference = _extractReference(body);
    final date = _extractDate(body);

    return SmsParseResult(
      amount: amount,
      isDebit: isDebit,
      merchant: merchant ?? bank,
      reference: reference,
      date: date,
      bank: bank,
    );
  }

  String? _identifyBank(String sender, String body) {
    for (final entry in _senderBankMap.entries) {
      if (sender.toUpperCase().contains(entry.key)) return entry.value;
    }
    // Fallback: check body for bank-like patterns
    final bankNames = ['SBI', 'HDFC', 'ICICI', 'Axis', 'Kotak', 'PNB', 'IndusInd', 'Yes Bank', 'IDFC'];
    for (final name in bankNames) {
      if (body.toUpperCase().contains(name.toUpperCase())) return name;
    }
    return null;
  }

  double? _extractAmount(String body) {
    for (final pattern in _amountPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final amountStr = match.group(1)!.replaceAll(',', '');
        return double.tryParse(amountStr);
      }
    }
    return null;
  }

  String? _extractMerchant(String body) {
    for (final pattern in _merchantPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final merchant = match.group(1)?.trim();
        if (merchant != null && merchant.isNotEmpty && merchant.length > 2) {
          return merchant;
        }
      }
    }
    return null;
  }

  String? _extractReference(String body) {
    final match = _refPattern.firstMatch(body);
    return match?.group(1)?.trim();
  }

  DateTime? _extractDate(String body) {
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        try {
          final g1 = match.group(1)!;
          final g2 = match.group(2)!;
          final g3 = match.group(3)!;

          // DD-Mon-YYYY
          if (_months.containsKey(g2.toLowerCase())) {
            return DateTime(int.parse(g3), _months[g2.toLowerCase()]!, int.parse(g1));
          }
          // YYYY-MM-DD
          if (g1.length == 4) {
            return DateTime(int.parse(g1), int.parse(g2), int.parse(g3));
          }
          // DD-MM-YYYY or DD-MM-YY
          final year = int.parse(g3);
          return DateTime(
            year < 100 ? 2000 + year : year,
            int.parse(g2),
            int.parse(g1),
          );
        } catch (_) {}
      }
    }
    return null;
  }
}
