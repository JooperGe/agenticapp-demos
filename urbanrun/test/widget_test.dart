import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/app.dart';

void main() {
  testWidgets('renders the Urbanrun game host', (tester) async {
    await tester.pumpWidget(const UrbanrunApp());

    expect(
      find.byWidgetPredicate((widget) => widget is GameWidget),
      findsOneWidget,
    );
    expect(find.text('URBANRUN'), findsOneWidget);
  });
}
