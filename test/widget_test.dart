import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/main.dart';

void main() {
  testWidgets('App boots to root scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const AuroraApp());
    await tester.pump();

    // Home header renders.
    expect(find.text('Aurora'), findsWidgets);
  });
}
