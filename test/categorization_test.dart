import 'package:flutter_test/flutter_test.dart';
import 'package:yourca/features/categories/categorization_service.dart';

void main() {
  final service = CategorizationService.instance;

  group('CategorizationService', () {
    group('Food & Dining', () {
      test('matches Swiggy', () => expect(service.categorize('SWIGGY'), 'Food & Dining'));
      test('matches Zomato', () => expect(service.categorize('ZOMATO ORDER'), 'Food & Dining'));
      test('matches Dominos', () => expect(service.categorize('DOMINOS PIZZA'), 'Food & Dining'));
    });

    group('Transport', () {
      test('matches Uber', () => expect(service.categorize('uber'), 'Transport'));
      test('matches IRCTC', () => expect(service.categorize('IRCTC TICKET'), 'Transport'));
      test('matches OLA', () => expect(service.categorize('OLA Cabs'), 'Transport'));
    });

    group('Shopping', () {
      test('matches Amazon', () => expect(service.categorize('amazon.in purchase'), 'Shopping'));
      test('matches Flipkart', () => expect(service.categorize('FLIPKART'), 'Shopping'));
    });

    group('Utilities', () {
      test('matches Jio recharge', () => expect(service.categorize('JIO recharge'), 'Utilities'));
      test('matches BSNL', () => expect(service.categorize('BSNL broadband'), 'Utilities'));
    });

    group('Income credit', () {
      test('returns Income for credits', () {
        expect(
            service.categorizeWithType('NEFT transfer', isCredit: true),
            'Income');
      });
    });

    test('falls back to Other for unknown merchants', () {
      expect(service.categorize('RANDOM XYZ 12345'), 'Other');
    });

    group('User corrections', () {
      test('user corrections take priority over keywords', () {
        service.loadUserCorrections({'swiggy': 'Entertainment'});
        expect(service.categorize('Swiggy order'), 'Entertainment');
        // Reset
        service.loadUserCorrections({});
      });
    });
  });
}
