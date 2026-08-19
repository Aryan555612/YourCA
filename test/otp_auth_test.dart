import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourca/features/auth/auth_provider.dart';
import 'package:yourca/features/auth/email_otp_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthNotifier OTP Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('sendEmailOtp throws exception on Brevo API HTTP error', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      final notifier = container.read(authNotifierProvider.notifier);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid API Key'}),
          401,
        );
      });

      expect(
        () => notifier.sendEmailOtp(
          email: 'test@example.com',
          httpClient: mockClient,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('sendEmailOtp succeeds and caches pending OTP on Brevo HTTP 201', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      final notifier = container.read(authNotifierProvider.notifier);

      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://api.brevo.com/v3/smtp/email');
        return http.Response(
          jsonEncode({'messageId': '<test@brevo.com>'}),
          201,
        );
      });

      await notifier.sendEmailOtp(
        email: 'test@example.com',
        httpClient: mockClient,
      );

      final storedCode = prefs.getString('pending_otp_code');
      final storedEmail = prefs.getString('pending_otp_email');
      final storedExpiry = prefs.getInt('pending_otp_expiry');

      expect(storedCode, isNotNull);
      expect(storedCode!.length, 6);
      expect(storedEmail, 'test@example.com');
      expect(storedExpiry, isNotNull);
      expect(storedExpiry! > DateTime.now().millisecondsSinceEpoch, isTrue);
    });

    test('verifyEmailOtp accepts exact real OTP code and rejects incorrect code', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      final notifier = container.read(authNotifierProvider.notifier);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'messageId': '<test@brevo.com>'}), 201);
      });

      // 1. Send real OTP
      await notifier.sendEmailOtp(email: 'test@example.com', httpClient: mockClient);
      final realCode = prefs.getString('pending_otp_code')!;

      // 2. Reject incorrect code
      expect(
        () => notifier.verifyEmailOtp(email: 'test@example.com', otp: '000000'),
        throwsA(isA<Exception>()),
      );

      // 3. Verify exact real code succeeds
      await notifier.verifyEmailOtp(email: 'test@example.com', otp: realCode);
      expect(container.read(stableUserIdProvider), isNotNull);
    });

    test('verifyEmailOtp works across multiple different emails with real generated OTPs', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      final notifier = container.read(authNotifierProvider.notifier);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'messageId': '<test@brevo.com>'}), 201);
      });

      // Sign in with Email 1
      await notifier.sendEmailOtp(email: 'user1@domain.com', httpClient: mockClient);
      final code1 = prefs.getString('pending_otp_code')!;
      await notifier.verifyEmailOtp(email: 'user1@domain.com', otp: code1);
      final uid1 = container.read(stableUserIdProvider);
      expect(uid1, isNotNull);

      // Sign out
      await notifier.signOut();
      expect(container.read(stableUserIdProvider), isNull);

      // Sign in with Email 2
      await notifier.sendEmailOtp(email: 'user2@domain.com', httpClient: mockClient);
      final code2 = prefs.getString('pending_otp_code')!;
      await notifier.verifyEmailOtp(email: 'user2@domain.com', otp: code2);
      final uid2 = container.read(stableUserIdProvider);
      expect(uid2, isNotNull);
      expect(uid2, isNot(equals(uid1))); // Distinct accounts get distinct stable UIDs!
    });
  });

  group('EmailOtpScreen Widget Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('Renders email input form and Send OTP button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EmailOtpScreen(),
          ),
        ),
      );

      expect(find.text('Sign in with\nEmail OTP'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
    });
  });
}
