import 'package:comboio/logic/radars.dart';
import 'package:comboio/services/speed_fix_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Trevo da Anhanguera (10/11): o radar marcado e vizinhos de outras fontes.
  const marcado = FixedRadar(1, -21.21092, -47.75864, RadarKind.fixed, 0, 183);

  test('mesmo radar de outra fonte (perto, mesmo sentido) é gêmeo', () {
    const gemeo = FixedRadar(2, -21.21060, -47.75870, RadarKind.fixed, 60, 180);
    const semSentido = FixedRadar(3, -21.21100, -47.75860, RadarKind.fixed, 0, -1);
    expect(SpeedFixService.twinsOf(marcado, [marcado, gemeo, semSentido]).map((r) => r.id), [2, 3]);
  });

  test('pista contrária, outro tipo ou longe não são gêmeos', () {
    const contraMao = FixedRadar(4, -21.21080, -47.75864, RadarKind.fixed, 60, 3);
    const sinal = FixedRadar(5, -21.21092, -47.75860, RadarKind.redLight, 0, 183);
    const outraAlca = FixedRadar(6, -21.20924, -47.75857, RadarKind.fixed, 0, 90); // 187 m
    expect(SpeedFixService.twinsOf(marcado, [contraMao, sinal, outraAlca]), isEmpty);
  });
}
