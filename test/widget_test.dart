import 'package:flutter_test/flutter_test.dart';
import 'package:floatilla/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const FloatillaApp());
    expect(find.text('Chart'), findsOneWidget);
  });
}
