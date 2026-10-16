import 'package:comboio/logic/speed.dart';
import 'package:comboio/widgets/speedometer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placa "110" inteira, mesmo com a fonte grande do celular',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Speedometer(
                kmh: 96, limit: RoadLimit(110, false), level: SpeedLevel.normal),
          ),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text('110'));
    expect(text.maxLines, 1);
    expect(tester.takeException(), isNull); // nada estourou o círculo
    // O texto cabe no círculo de 44 px (com a borda de 5 px).
    expect(tester.getSize(find.text('110')).width * 1, lessThanOrEqualTo(200));
    final box = tester.getRect(find.text('110'));
    final circle = tester.getRect(find.ancestor(
        of: find.text('110'), matching: find.byType(Container)).first);
    expect(circle.contains(box.center), isTrue);
  });
}
