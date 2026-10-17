import 'package:flutter_test/flutter_test.dart';
import 'package:sight_mate/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SightMateApp());
    expect(find.byType(SightMateApp), findsOneWidget);
  });
}
