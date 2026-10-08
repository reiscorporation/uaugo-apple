// ============================================================================
// about_screen.dart — Tela "Sobre"
//
// O que faz: Autoria (Ricardo Reis / HelpAITech, foto e avatar) e créditos das
//   fontes de dados exigidos pelas licenças (OpenStreetMap, Pardal, PRF...).
// Quem usa: Home (rodapé "Desenvolvido por") e Configurações.
// Onde mexer: Versão exibida: AboutScreen.version.
// ============================================================================

import 'package:flutter/material.dart';

/// Sobre o app: autoria (HelpAITech) e créditos das fontes de dados.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget credit(String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall),
            Text(text, style: theme.textTheme.bodySmall),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre')),
      body: SafeArea(
        top: false,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          // App
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/branding/comboio_logo.png',
                  width: 120, height: 120),
            ),
          ),
          const SizedBox(height: 12),
          Text('Convoyar',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text('Viagens em grupo, de moto ou de carro · versão $version',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 28),

          // Autoria
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Text('Desenvolvido por',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Image.asset('assets/branding/helpaitech_logo.png', height: 110),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ClipOval(
                    // Na foto o rosto fica no alto: amplia em volta dele.
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Transform.scale(
                        scale: 2.1,
                        alignment: const Alignment(0.02, -0.62),
                        child: Image.asset('assets/branding/fundador_foto.webp',
                            fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ClipOval(
                    child: Image.asset('assets/branding/fundador_avatar.png',
                        width: 96, height: 96, fit: BoxFit.cover),
                  ),
                ]),
                const SizedBox(height: 10),
                const Text('Ricardo Reis',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Text('Fundador da HelpAITech · proprietário do Convoyar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                    '© 2026 HelpAITech e Ricardo Reis. Todos os direitos '
                    'reservados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          // Créditos das fontes de dados (exigidos pelas licenças)
          Text('Dados e serviços', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          credit('Mapas, rotas e busca de lugares', 'Google Maps Platform'),
          credit('Radares fixos e limites de velocidade',
              'Projeto Pardal (ODbL) – DNIT, ANTT, DERs, prefeituras e '
                  '© colaboradores do OpenStreetMap'),
          credit('Trechos de fiscalização por radar portátil',
              'Polícia Rodoviária Federal (lista oficial, Res. CONTRAN 798/20); '
                  'traçado das rodovias: DNIT/SNV'),
          credit('Alertas da comunidade',
              'Reportados pelos próprios pilotos do Convoyar'),
        ]),
      ),
    );
  }
}
