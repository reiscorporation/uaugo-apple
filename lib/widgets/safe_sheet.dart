// ============================================================================
// safe_sheet.dart — Painel de baixo que nunca fica escondido
//
// O que faz: Abre um painel de baixo (bottom sheet) que respeita as barras do
//   Android/iPhone e ROLA quando o conteúdo é maior que a tela. O padrão do
//   Flutter limita o painel a pouco mais da metade da tela e corta o resto,
//   que acabava atrás da barra de navegação do Android.
// Quem usa: MapScreen (voz, alertas, clube, ...), PlanScreen.
// ============================================================================

import 'package:flutter/material.dart';

/// Igual a showModalBottomSheet, mas pode crescer até 90% da tela e rolar.
Future<T?> showSafeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
      child: SingleChildScrollView(child: builder(ctx)),
    ),
  );
}
