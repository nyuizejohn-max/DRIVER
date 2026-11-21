
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('Driver app starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const DriverApp());

    expect(find.byType(DriverApp), findsOneWidget);
  });
}
