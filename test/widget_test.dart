// YourCA smoke test — verifies the app starts without crashing.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourca/app.dart';
import 'package:yourca/features/auth/auth_provider.dart';

void main() {
  testWidgets('YourCA app smoke test', (WidgetTester tester) async {
    // Mock SharedPreferences for the test
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Build the app wrapped in ProviderScope with overridden preferences
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const YourCAApp(),
      ),
    );
    // Allow async startup to settle
    await tester.pump();
    // Just verify it renders without crashing
    expect(find.byType(YourCAApp), findsOneWidget);
  });
}
