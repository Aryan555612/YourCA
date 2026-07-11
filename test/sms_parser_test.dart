import 'package:flutter_test/flutter_test.dart';
import 'package:yourca/features/sms/bank_sms_parser.dart';

void main() {
  final parser = BankSmsParser.instance;

  group('BankSmsParser', () {
    // ── HDFC ────────────────────────────────────────────────────────────────
    group('HDFC', () {
      test('parses HDFC debit SMS', () {
        const sms =
            'Rs.500.00 debited from your HDFC Bank A/c XX0123 on 10-07-2026 at Swiggy. '
            'UPI Ref No 412345678901. Available balance Rs.12,500.00';

        final result = parser.parse(body: sms, sender: 'HDFCBK');

        expect(result, isNotNull);
        expect(result!.amount, 500.0);
        expect(result.isDebit, true);
        expect(result.bank, 'HDFC');
      });

      test('parses HDFC credit SMS', () {
        const sms =
            'Rs.25,000.00 credited to your HDFC Bank A/c XX0123 on 10-07-2026. '
            'UPI Ref 567890123456. Info: SALARY. Balance Rs.37,500.00';

        final result = parser.parse(body: sms, sender: 'HDFCBK');

        expect(result, isNotNull);
        expect(result!.amount, 25000.0);
        expect(result.isDebit, false);
      });
    });

    // ── ICICI ────────────────────────────────────────────────────────────────
    group('ICICI', () {
      test('parses ICICI debit SMS with UPI', () {
        const sms =
            'INR 1,250.00 debited from your ICICI Bank Account XX1234 on 10-Jul-2026. '
            'VPA swiggy@icici. Ref 123456789012';

        final result = parser.parse(body: sms, sender: 'ICICIB');

        expect(result, isNotNull);
        expect(result!.amount, 1250.0);
        expect(result.isDebit, true);
        expect(result.bank, 'ICICI');
      });
    });

    // ── SBI ──────────────────────────────────────────────────────────────────
    group('SBI', () {
      test('parses SBI withdrawal SMS', () {
        const sms =
            'Your A/c No. XX5678 is debited by Rs. 3,000 on 10/07/2026 '
            'towards IRCTC TICKET. Avbl Bal: Rs.8,450.00';

        final result = parser.parse(body: sms, sender: 'SBIINB');

        expect(result, isNotNull);
        expect(result!.amount, 3000.0);
        expect(result.isDebit, true);
        expect(result.bank, 'SBI');
      });
    });

    // ── Non-bank SMS ─────────────────────────────────────────────────────────
    test('returns null for non-bank SMS', () {
      const sms = 'Your OTP for login is 123456. Valid for 10 minutes.';
      final result = parser.parse(body: sms, sender: 'TMJIO1');
      expect(result, isNull);
    });

    test('returns null for SMS without amount', () {
      const sms = 'Your HDFC account has been updated. Please check.';
      final result = parser.parse(body: sms, sender: 'HDFCBK');
      expect(result, isNull);
    });

    // ── Amount extraction ────────────────────────────────────────────────────
    group('Amount extraction', () {
      test('handles comma-separated amounts', () {
        const sms =
            'Rs.1,25,000 debited from your SBI account. Ref 123456';
        final result = parser.parse(body: sms, sender: 'SBIINB');
        expect(result?.amount, 125000.0);
      });

      test('handles decimal amounts', () {
        const sms =
            'INR 99.99 debited at Amazon. Ref 9876543210';
        final result = parser.parse(body: sms, sender: 'HDFCBK');
        expect(result?.amount, 99.99);
      });
    });

    // ── Merchant Extraction & Balance Parsing ────────────────────────────────
    group('Merchant and Balance parsing', () {
      test('parses Lenskart payment correctly', () {
        const sms =
            'Dear Customer, Rs.998.00 paid To: LENSKART SOLUTIONS LIMITED / Fro. Clear Balance. Ref No: 123456.';
        final result = parser.parse(body: sms, sender: 'SBIINB');
        expect(result, isNotNull);
        expect(result!.amount, 998.0);
        expect(result.isDebit, true);
        expect(result.merchant, 'Lenskart Solutions Limited');
      });

      test('parses balance SMS correctly', () {
        const sms =
            'Clear Balance in Your A/C XX1234 is INR 526.08 on 11-07-2026. Ref 123456';
        final result = parser.parseBalance(body: sms, sender: 'SBIINB');
        expect(result, isNotNull);
        expect(result!.balance, 526.08);
        expect(result.bank, 'SBI');
        expect(result.accountSuffix, '1234');
      });

      test('parses alternative balance format', () {
        const sms =
            'Avl Bal: INR 1,234.56 on your HDFC Bank Ac XX5678';
        final result = parser.parseBalance(body: sms, sender: 'HDFCBK');
        expect(result, isNotNull);
        expect(result!.balance, 1234.56);
        expect(result.bank, 'HDFC');
        expect(result.accountSuffix, '5678');
      });
    });
  });
}
