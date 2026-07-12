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

/// Parsed balance from a bank SMS.
class BalanceParseResult {
  final double balance;
  final String bank;
  final String? accountSuffix; // last 4 digits of account
  final DateTime parsedAt;

  const BalanceParseResult({
    required this.balance,
    required this.bank,
    this.accountSuffix,
    required this.parsedAt,
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
    'MUCBNK': 'MUCB',
    'MUCB': 'MUCB',
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

  // ── HIGH PRIORITY: UPI To:NAME/From: pattern (most Indian banks) ─────────
  // FIXED: Now handles full merchant names including "LENSKART SOLUTIONS LIMITED"
  // Pattern captures everything between "To:" and the "/" separator or line end
  // Also handles "/Fro." abbreviation used by some banks (MUCB, etc.) and arbitrary slash suffixes like "/F."
  static final _upiToPattern = RegExp(
    r'(?:UPI[/\s]*[\w]+[/\s]*)?To[:\s]+([A-Za-z0-9][A-Za-z0-9\s\.\-\_&]{2,80}?)(?:\s*/|(?:\.?\s*Clear\b)|\.\s*$|\s*$)',
    caseSensitive: false,
  );

  static final _upiFromPattern = RegExp(
    r'From[:\s]+([A-Za-z][A-Za-z\s\-\.]{2,50}?)(?:\s*/|(?:\s+Ref)|\s+on\b|\.\s|\.$|\s*$)',
    caseSensitive: false,
  );

  // ── MEDIUM PRIORITY: Generic merchant patterns ───────────────────────────
  static final _merchantPatternsGeneric = [
    RegExp(r'(?:trf to|transfer to|paid to|sent to)[:\s]+([A-Za-z0-9\s\.\-\_]+?)(?:\s+ref|\s+on|\s*\.|,|$)',
        caseSensitive: false),
    RegExp(r'VPA[:\s]+([A-Za-z0-9@\.\-\_]+)', caseSensitive: false),
    RegExp(r'(?:at|merchant)[:\s]+([A-Za-z0-9\s\.\-\_]+?)(?:\s+on|\s+ref|\s*\.|,|$)',
        caseSensitive: false),
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

  // ── Balance patterns — extracts "Clear Balance in Your A/C is INR 526.08"
  //    or "Avl Bal: INR 1,234.56" or "Available balance: Rs. 5,000" ─────────
  static final _balancePatterns = [
    RegExp(
      r'(?:Clear\s+)?[Bb]al(?:ance)?.*?(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    ),
    RegExp(
      r'[Aa]vl\.?\s*[Bb]al(?:ance)?.*?(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    ),
    RegExp(
      r'[Aa]vailable\s+[Bb]al(?:ance)?.*?(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    ),
    RegExp(
      r'[Aa]/[Cc]\s+[Bb]al(?:ance)?.*?(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d*)\s+.*?[Bb]al',
      caseSensitive: false,
    ),
  ];

  // ── Account number pattern ──────────────────────────────────────────────
  static final _accountPattern = RegExp(
    r'(?:a/c|acct|account|ac)\s+(?:no\.?\s+)?(?:XX+|x+)(\d{4})',
    caseSensitive: false,
  );

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

    final merchant = _extractMerchant(body, isDebit: isDebit);
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

  /// Attempts to parse bank balance from an SMS.
  /// Returns null if no balance information found.
  BalanceParseResult? parseBalance({
    required String body,
    required String sender,
  }) {
    final bank = _identifyBank(sender, body) ?? 'Bank';

    double? balance;
    for (final pattern in _balancePatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final balStr = match.group(1)?.replaceAll(',', '');
        balance = double.tryParse(balStr ?? '');
        if (balance != null) break;
      }
    }

    if (balance == null) return null;

    final accountMatch = _accountPattern.firstMatch(body);
    final accountSuffix = accountMatch?.group(1);

    return BalanceParseResult(
      balance: balance,
      bank: bank,
      accountSuffix: accountSuffix,
      parsedAt: DateTime.now(),
    );
  }

  String? _identifyBank(String sender, String body) {
    // 1. Clean sender ID to extract the core alphabetic header (usually 6 letters)
    // E.g., "JD-MUCBNK-S" -> ["JD", "MUCBNK", "S"]
    String cleanSender = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    final parts = cleanSender.split('-');
    
    // Find the part that is likely the bank header (usually 4 to 8 characters)
    String header = '';
    for (final part in parts) {
      if (part.length >= 4 && part.length <= 8) {
        header = part;
        break;
      }
    }
    if (header.isEmpty && parts.isNotEmpty) {
      header = parts.last;
    }

    // Check if the header matches any of our predefined bank mappings
    for (final entry in _senderBankMap.entries) {
      if (header.contains(entry.key.toUpperCase()) || sender.toUpperCase().contains(entry.key.toUpperCase())) {
        return entry.value;
      }
    }

    // Check if it is a transaction notification by scanning for keywords
    final hasAmount = _amountPatterns.any((p) => p.hasMatch(body));
    final isTx = _debitPattern.hasMatch(body) || _creditPattern.hasMatch(body);
    final hasAcct = RegExp(r'\b(?:a/c|acct|account|card|xx\d{2,})\b', caseSensitive: false).hasMatch(body);

    if (hasAmount && isTx && hasAcct) {
      // It is a valid transaction! Identify bank by cleaning the header
      if (header.isNotEmpty) {
        String bankName = header;
        // Strip common suffixes
        if (bankName.endsWith('BNK')) bankName = bankName.substring(0, bankName.length - 3);
        if (bankName.endsWith('BK')) bankName = bankName.substring(0, bankName.length - 2);
        if (bankName.endsWith('SMS')) bankName = bankName.substring(0, bankName.length - 3);
        if (bankName.isNotEmpty) return bankName;
      }
      return 'Bank';
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

  String? _extractMerchant(String body, {bool isDebit = true}) {
    // ── STEP 1: High-priority UPI To:/From: pattern ──────────────────────
    if (isDebit) {
      final toMatch = _upiToPattern.firstMatch(body);
      if (toMatch != null) {
        final name = toMatch.group(1)?.trim();
        if (name != null && name.length > 2 && !_isNoise(name)) {
          return _cleanMerchantName(name);
        }
      }
    } else {
      final fromMatch = _upiFromPattern.firstMatch(body);
      if (fromMatch != null) {
        final name = fromMatch.group(1)?.trim();
        if (name != null && name.length > 2 && !_isNoise(name)) {
          return _cleanMerchantName(name);
        }
      }
    }

    // ── STEP 2: Also try the other direction as fallback ─────────────────
    if (isDebit) {
      final fromMatch = _upiFromPattern.firstMatch(body);
      if (fromMatch != null) {
        final name = fromMatch.group(1)?.trim();
        if (name != null && name.length > 4 && !_isNoise(name) && !_looksLikeBankCode(name)) {
          return _cleanMerchantName(name);
        }
      }
    } else {
      final toMatch = _upiToPattern.firstMatch(body);
      if (toMatch != null) {
        final name = toMatch.group(1)?.trim();
        if (name != null && name.length > 2 && !_isNoise(name)) {
          return _cleanMerchantName(name);
        }
      }
    }

    // ── STEP 3: Generic patterns ──────────────────────────────────────────
    for (final pattern in _merchantPatternsGeneric) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final merchant = match.group(1)?.trim();
        if (merchant != null && merchant.isNotEmpty && merchant.length > 2 && !_isNoise(merchant)) {
          return _cleanMerchantName(merchant);
        }
      }
    }
    return null;
  }

  /// Returns true if the extracted name is noise/generic (not a real merchant).
  bool _isNoise(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.contains('report') ||
        lower.contains('block') ||
        lower.contains('unauthorized') ||
        lower.contains('fraud') ||
        lower.contains('if not done') ||
        lower.contains('if not you')) {
      return true;
    }

    const noiseWords = {
      'your', 'the', 'on', 'at', 'of', 'for', 'a', 'an', 'is', 'are',
      'bank', 'ref', 'no', 'transaction', 'amount', 'balance', 'account',
      'upi', 'neft', 'imps', 'rtgs', 'inr', 'rs', 'clear', 'info',
      'report', 'fro', 'from', 'limited', 'solutions', // added noise
    };
    // Check for exact noise match
    if (noiseWords.contains(lower)) return true;
    if (lower.length <= 2) return true;
    // Check if name is purely numeric
    if (RegExp(r'^\d+$').hasMatch(lower)) return true;
    return false;
  }

  /// Returns true if name looks like a bank short code (e.g. "PAT", "SBI", "HDFC")
  bool _looksLikeBankCode(String name) {
    // Short all-caps codes like "PAT", "HDFC", "SBI" are bank codes
    final cleaned = name.trim();
    if (cleaned.length <= 5 && cleaned == cleaned.toUpperCase()) return true;
    return false;
  }

  /// Clean up extracted merchant name — trim, title-case, remove trailing dots/slashes.
  String _cleanMerchantName(String name) {
    // Remove trailing slashes, dots, "Fro", "From" artifacts
    String cleaned = name.trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\.\/]+$'), '')
        .replaceAll(RegExp(r'\s*/?[Ff]ro\.?\s*$'), '') // remove trailing "Fro."
        .trim();

    // Remove trailing noise words that crept in
    final trailingNoise = RegExp(
      r'\s+(fro|from|clear|balance)\s*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(trailingNoise, '').trim();

    // If the result is a noise word, return as-is (caller will fall through)
    if (_isNoise(cleaned)) return name.trim();

    // Title-case if all upper
    if (cleaned == cleaned.toUpperCase() && cleaned.length > 3) {
      return cleaned.split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      }).join(' ');
    }
    return cleaned;
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
