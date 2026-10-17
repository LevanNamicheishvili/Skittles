import 'package:flutter_test/flutter_test.dart';

import 'package:team_ai_game/main.dart';

void main() {
  testWidgets('shows the phase 0 placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const TeamAiGameApp());

    expect(find.text('ერთად მოიფიქრე, მაშინვე ითამაშე'), findsOneWidget);
  });
}
