import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/ui/kit.dart';

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

void main() {
  for (final kind in ArriveKind.values) {
    testWidgets('a ${kind.name} arrival keeps the state inside it', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Arrive(kind: kind, child: const _Probe())));
      final before = tester.state(find.byType(_Probe));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));
      expect(identical(tester.state(find.byType(_Probe)), before), isTrue, reason: 'the child was rebuilt from scratch');
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });
  }

  testWidgets('reduced motion shows things at once', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.ltr, child: Arrive(kind: ArriveKind.card, child: SizedBox(width: 10, height: 10))),
    ));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
  });
}
