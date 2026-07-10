// YourCA smoke test — verifies the app starts without crashing.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yourca/app.dart';

void main() {
  testWidgets('YourCA app smoke test', (WidgetTester tester) async {
    // Build the app wrapped in ProviderScope (required by Riverpod)
    await tester.pumpWidget(const ProviderScope(child: YourCAApp()));
    // Allow async startup to settle
    await tester.pump();
    // Just verify it renders without crashing
    expect(find.byType(YourCAApp), findsOneWidget);
  });
}
