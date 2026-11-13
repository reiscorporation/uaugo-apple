import 'package:comboio/logic/costs.dart';
import 'package:comboio/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combustão: litros pelo km/l', () {
    final e = tripEnergy(120000, const FuelPrefs(enabled: true, kmPerLiter: 12, pricePerLiter: 6));
    expect(e.liters, closeTo(10, 0.001));
    expect(e.kwh, 0);
    expect(e.cost, closeTo(60, 0.001));
  });

  test('elétrico: kWh pelo km/kWh', () {
    final e = tripEnergy(120000, const FuelPrefs(
        enabled: true, energy: EnergyType.electric, kmPerKwh: 6, pricePerKwh: 0.8));
    expect(e.kwh, closeTo(20, 0.001));
    expect(e.liters, 0);
    expect(e.cost, closeTo(16, 0.001));
  });

  test('plug-in: elétrico até a autonomia, combustível no resto', () {
    const f = FuelPrefs(enabled: true, energy: EnergyType.phev,
        kmPerLiter: 15, pricePerLiter: 6, kmPerKwh: 5, pricePerKwh: 1, evRangeKm: 50);
    final e = tripEnergy(200000, f);
    expect(e.kwh, closeTo(10, 0.001)); // 50 km / 5
    expect(e.liters, closeTo(10, 0.001)); // 150 km / 15
    expect(e.cost, closeTo(70, 0.001));
    final curta = tripEnergy(30000, f);
    expect(curta.liters, 0);
    expect(curta.kwh, closeTo(6, 0.001));
  });

  test('pronto só com os números do tipo de energia', () {
    expect(const FuelPrefs(enabled: true, energy: EnergyType.electric, kmPerKwh: 6, pricePerKwh: 1).ready, isTrue);
    expect(const FuelPrefs(enabled: true, energy: EnergyType.phev, kmPerKwh: 6, pricePerKwh: 1).ready, isFalse);
  });
}
