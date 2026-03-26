import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_plotter/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterPlotterApp());
    expect(find.text('Chart'), findsOneWidget);
  });
}
