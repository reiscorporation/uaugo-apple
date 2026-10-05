import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comboio/main.dart';

// O app real depende do Firebase inicializado; aqui só garantimos que o
// widget raiz existe e compila. Os fluxos são testados no emulador
// (scripts/testar-local.ps1).
void main() {
  test('ComboioApp é o widget raiz', () {
    expect(const ComboioApp(), isA<StatelessWidget>());
  });
}
