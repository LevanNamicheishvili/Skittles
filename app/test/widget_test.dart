import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skittles/main.dart';

void main() {
  testWidgets('opens the editor on the sample level at the minimum window size', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SkittlesApp());

    expect(find.text('Skittles'), findsOneWidget);
    expect(find.text('Castle Story'), findsWidgets);
    expect(find.textContaining('Winnable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
