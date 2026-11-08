import 'package:flutter_test/flutter_test.dart';

import 'package:radiotop/main.dart';

void main() {
  testWidgets('RadioTop opens the station browser', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RadioTopApp());

    expect(find.text('Explore stations'), findsOneWidget);
  });
}
