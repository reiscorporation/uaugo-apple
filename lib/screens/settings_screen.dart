// ============================================================================
// settings_screen.dart — Configurações
//
// O que faz: Tela (sempre ligada, trânsito, mapa noturno, economia de
//   bateria), rotas, avisos (radar, polícia, lombadas, chuva, metade), voz,
//   "Usar sem internet" e Sobre.
// Quem usa: HomeScreen (engrenagem) e MapScreen (Voz → Mais configurações).
// Onde mexer: Valores e padrões: services/app_settings.dart.
// ============================================================================

import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/offline_voice_service.dart';

import '../logic/speech.dart';
import '../services/app_settings.dart';
import '../services/poi_service.dart';
import '../services/speed_service.dart';
import '../logic/voice_commands.dart';
import '../services/voice_command_service.dart';
import '../services/voice_service.dart';
import '../services/auth_service.dart';
import 'about_screen.dart';
import 'admin_screen.dart';
import '../services/club_service.dart';
import 'login_screen.dart';
import 'terms_screen.dart';
import '../l10n/i18n.dart';
import '../services/media_service.dart';

/// Escolher estados e baixar os dados para usar sem internet.
class _OfflineScreen extends StatefulWidget {
  const _OfflineScreen();

  @override
  State<_OfflineScreen> createState() => _OfflineScreenState();
}

/// Estados disponíveis, já baixados e escolhidos.
class _OfflineScreenState extends State<_OfflineScreen> {
  List<String> _ufs = const [];
  final Set<String> _stored = {};
  final Set<String> _selected = {};
  String? _busy;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Lista os estados e marca os já baixados.
  Future<void> _init() async {
    final ufs = await SpeedService.instance.availableUfs();
    for (final uf in ufs) {
      if (await SpeedService.instance.isStored(uf)) _stored.add(uf);
    }
    if (!mounted) return;
    setState(() {
      _ufs = ufs;
      _loading = false;
    });
  }

  /// Baixa os estados escolhidos (limites + lombadas/postos/pedágios).
  Future<void> _download() async {
    for (final uf in _selected.toList()..sort()) {
      setState(() => _busy = uf);
      final a = await SpeedService.instance.prefetch(uf);
      await PoiService.instance.prefetch(uf);
      if (!mounted) return;
      setState(() {
        if (a) _stored.add(uf);
        _selected.remove(uf);
      });
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Usar sem internet'))),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text(
                    tr('Escolha os estados por onde vai passar. Os dados ficam no celular e são usados mesmo sem sinal: limites de velocidade, lombadas e postos policiais. A rota calculada antes de sair, a narração e os radares também funcionam sem internet.\n\nO mapa do Google não pode ser baixado (regra do Google): sem sinal, ele mostra só as áreas vistas recentemente.')),
                const SizedBox(height: 16),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final uf in _ufs)
                    FilterChip(
                      avatar: _stored.contains(uf)
                          ? const Icon(Icons.check_circle, size: 18)
                          : null,
                      label: Text(uf),
                      selected: _selected.contains(uf),
                      onSelected: _busy != null
                          ? null
                          : (v) => setState(() =>
                              v ? _selected.add(uf) : _selected.remove(uf)),
                    ),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _selected.isEmpty || _busy != null ? null : _download,
                  icon: _busy != null
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(_busy != null
                      ? tr('Baixando {0}...', [_busy])
                      : tr('Baixar {0} {1}', [_selected.length, _selected.length == 1 ? tr('estado') : tr('estados')])),
                ),
                const SizedBox(height: 8),
                Text(tr('✓ = já baixado e atualizado'),
                    style: TextStyle(fontSize: 12)),
              ]),
      ),
    );
  }
}

/// Conta: entrar (se anônima) ou ver a conta, confirmar o e-mail e sair.
class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService.changes,
      builder: (context, _) {
        if (AuthService.isAnonymous) {
          return ListTile(
            leading: const Icon(Icons.account_circle_outlined, size: 32),
            title: Text(tr('Entrar ou criar conta')),
            subtitle: Text(
                tr('Necessária para expedições, alertas e clube. Navegar sozinho funciona sem conta.')),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          );
        }
        return Column(children: [
          ListTile(
            leading: const Icon(Icons.account_circle, size: 32),
            title: Text(AuthService.missingName
                ? tr('Toque para pôr seu nome')
                : AuthService.displayName),
            subtitle: Text(AuthService.email),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => editAccountName(context),
          ),
          if (AuthService.needsVerification) ...[
            ListTile(
              leading: Icon(Icons.mark_email_unread_outlined,
                  color: Colors.amber),
              title: Text(tr('Confirme seu e-mail')),
              subtitle: Text(
                  tr('Enviamos um link para o seu e-mail. Depois de confirmar, toque em "Já confirmei".')),
            ),
            Padding(
              padding: EdgeInsets.only(left: 56),
              child: Wrap(children: [
                TextButton(
                  onPressed: AuthService.resendVerification,
                  child: Text(tr('Reenviar')),
                ),
                TextButton(
                  onPressed: AuthService.reload,
                  child: Text(tr('Já confirmei')),
                ),
              ]),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(tr('Sair da conta')),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('Sair da conta?')),
                  content: Text(
                      tr('Você pode entrar de novo quando quiser. Navegar sozinho continua funcionando sem conta.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('Cancelar'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('Sair'))),
                  ],
                ),
              );
              if (ok == true) await AuthService.signOut();
            },
          ),
        ]);
      },
    );
  }
}

/// Distância do 1º aviso e quantas vezes avisar até o ponto.
class _AlertPicker extends StatelessWidget {
  const _AlertPicker({
    required this.icon,
    required this.title,
    required this.meters,
    required this.repeats,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final int meters;
  final int repeats;
  final void Function(int meters, int repeats) onChanged;

  static const _distances = [300, 500, 750, 1000, 1500, 2000];

  @override
  Widget build(BuildContext context) {
    final at = alertThresholds(meters.toDouble(), repeats)
        .map((d) => d >= 1000
            ? '${(d / 1000).toStringAsFixed(d % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km'
            : '${d.round()} m')
        .join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          // Expanded: título longo quebra a linha em tela estreita (antes
          // estourava: "right overflowed by 25 pixels").
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ]),
        const SizedBox(height: 6),
        Text(tr('Primeiro aviso a')),
        Wrap(spacing: 6, children: [
          for (final m in _distances)
            ChoiceChip(
              label: Text(m >= 1000
                  ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km'
                  : '$m m'),
              selected: meters == m,
              onSelected: (_) => onChanged(m, repeats),
            ),
        ]),
        const SizedBox(height: 4),
        Text(tr('Quantas vezes avisar até o ponto')),
        Wrap(spacing: 6, children: [
          for (final r in const [1, 2, 3])
            ChoiceChip(
              label: Text('$r ${r == 1 ? 'vez' : 'vezes'}'),
              selected: repeats == r,
              onSelected: (_) => onChanged(meters, r),
            ),
        ]),
        Text(tr('Avisa a: {0}', [at]),
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// Configurações gerais: tela, rotas e voz.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Cadastra/troca/apaga o contato de emergência (fica só no celular).
  /// Vozes: as do UauGo (baixar uma vez, funcionam sem internet), as do
  /// celular e um atalho para baixar mais vozes do Google/Samsung.
  Future<void> _pickVoice(BuildContext context) async {
    final voice = VoiceService.instance;
    final ov = OfflineVoiceService.instance;
    await ov.refresh();
    final list = await voice.voices();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Voz')),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListenableBuilder(
            listenable: Listenable.merge([voice.voiceName, ov.installed, ov.downloading]),
            builder: (_, __) {
              final sel = voice.voiceName.value;
              Widget head(String t, [String? sub]) => Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t, style: Theme.of(ctx).textTheme.titleSmall),
                      if (sub != null)
                        Text(sub, style: Theme.of(ctx).textTheme.bodySmall),
                    ]),
                  );
              return ListView(shrinkWrap: true, children: [
                head(tr('Vozes do UauGo'),
                    tr('Baixe uma vez (cerca de 21 MB, de preferência no Wi-Fi). Funcionam sem internet.')),
                for (final v in OfflineVoice.catalog)
                  Builder(builder: (_) {
                    final has = ov.isInstalled(v);
                    final dl = ov.downloading.value;
                    final busy = dl.containsKey(v.id);
                    return ListTile(
                      leading: Icon(sel == v.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                      title: Text(tr('{0} · masculina', [v.label])),
                      subtitle: busy
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(dl[v.id] == null ? tr('Preparando...') : tr('Baixando...')),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: dl[v.id]),
                            ])
                          : (has
                              ? (v.note == null ? null : Text(tr(v.note!)))
                              : Text(v.note == null
                                  ? tr('Toque para baixar')
                                  : '${tr(v.note!)} · ${tr('Toque para baixar')}')),
                      trailing: busy
                          ? null
                          : has
                              ? PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (_) async {
                                    if (sel == v.key) await voice.clearVoice();
                                    await ov.remove(v);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'del', child: Text(tr('Apagar do celular'))),
                                  ],
                                )
                              : const Icon(Icons.download),
                      onTap: busy
                          ? null
                          : () async {
                              if (!has) {
                                final ok = await ov.download(v);
                                if (!ok) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(tr('Não deu para baixar a voz. Confira a internet e tente de novo.'))));
                                  }
                                  return;
                                }
                              }
                              await voice.setOfflineVoice(v);
                            },
                    );
                  }),
                head(tr('Vozes do celular')),
                ListTile(
                  leading: Icon(sel == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(tr('Automática')),
                  onTap: () async {
                    await voice.clearVoice();
                    voice.test(tr('Em 300 metros, vire à direita.'));
                  },
                ),
                for (final (i, v) in list.indexed)
                  ListTile(
                    leading: Icon(sel == v['name']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(voicePhoneLabel(v, i + 1)),
                    trailing: const Icon(Icons.volume_up),
                    onTap: () => voice.setVoice(v),
                  ),
                if (Platform.isIOS)
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(tr('Baixar vozes melhores no iPhone')),
                    subtitle: Text(tr('Ajustes > Acessibilidade > Conteúdo Falado > Vozes > Português (Brasil): baixe a Luciana ou o Felipe "Melhorada" ou "Premium". Depois volte aqui.')),
                  )
                else
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(tr('Baixar mais vozes do Google')),
                  subtitle: Text(tr('Abre o sistema: escolha Português (Brasil) e baixe as vozes. Depois volte aqui.')),
                  onTap: () async {
                    final ok = await const MethodChannel('uaugo/device')
                        .invokeMethod<bool>('openTtsSettings')
                        .catchError((_) => false);
                    if (ok != true && ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('Em Configurações do sistema > Conversão de texto em voz, baixe vozes em português.'))));
                    }
                  },
                ),
              ]);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fechar'))),
        ],
      ),
    );
  }

  /// Liga/desliga a voz de cada tipo de aviso.
  Future<void> _pickVoiceKinds(BuildContext context) async {
    final s = AppSettings.instance;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Voz por tipo de aviso')),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<AlertPrefs>(
            valueListenable: s.alerts,
            builder: (_, a, __) => ListView(shrinkWrap: true, children: [
              for (final e in voiceKinds.entries)
                CheckboxListTile(
                  dense: true,
                  title: Text(tr(e.value)),
                  value: !a.mutedVoice.contains(e.key),
                  onChanged: (on) {
                    final m = {...a.mutedVoice};
                    on == true ? m.remove(e.key) : m.add(e.key);
                    s.setAlerts(a.copyWith(mutedVoice: m));
                  },
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fechar'))),
        ],
      ),
    );
  }

  Future<void> _editEmergency(BuildContext context, (String, String)? c) async {
    final name = TextEditingController(text: c?.$1 ?? '');
    final phone = TextEditingController(text: c?.$2 ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Rola: com o teclado aberto e a letra grande do celular, os botões
        // ficavam por cima do texto (Galaxy, 17/11).
        scrollable: true,
        title: Text(tr('Contato de emergência')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Nome (ex.: Ana)')),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: tr('Celular com DDD'), hintText: '(16) 99999-9999'),
          ),
          const SizedBox(height: 8),
          Text(tr('Fica só no seu celular. Usado apenas quando você toca no SOS.'),
              style: TextStyle(fontSize: 12)),
          // Apagar fica no conteúdo, separado de Cancelar/Salvar.
          if (c != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade400, padding: EdgeInsets.zero),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(tr('Apagar contato')),
                onPressed: () => Navigator.pop(ctx, 'apagar'),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'salvar'), child: Text(tr('Salvar'))),
        ],
      ),
    );
    final s = AppSettings.instance;
    if (r == 'apagar') {
      await s.setEmergencyContact(null);
    } else if (r == 'salvar') {
      final digits = phone.text.replaceAll(RegExp(r'\D'), '');
      if (name.text.trim().isEmpty || digits.length < 10) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr('Contato não salvo: informe o nome e o celular com DDD.'))));
        }
        return;
      }
      await s.setEmergencyContact((name.text.trim(), digits));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final voice = VoiceService.instance;
    final theme = Theme.of(context);
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Configurações'))),
      body: SafeArea(
        top: false,
        child: ListView(children: [
          ValueListenableBuilder<(String, String)?>(
            valueListenable: s.emergencyContact,
            builder: (ctx, c, __) => Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              color: Colors.red.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.red),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.red,
                  child: Text('SOS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(tr('Contato de emergência'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(c == null
                    ? tr('Ninguém cadastrado. Segurando o SOS, abre um SMS pronto para essa pessoa com a sua localização.')
                    : tr('{0} · {1}\nNo SOS: SMS pronto para {2}.', [c.$1, c.$2, c.$1])),
                isThreeLine: c != null,
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editEmergency(ctx, c),
              ),
            ),
          ),
          section(tr('Conta')),
          const _AccountTile(),
          section(tr('Tela')),
          ValueListenableBuilder<bool>(
            valueListenable: s.keepScreenOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.brightness_high),
              title: Text(tr('Manter a tela ligada no mapa')),
              subtitle: Text(
                  tr('A tela não apaga enquanto o mapa estiver aberto. Navegando, ela fica sempre ligada. Use com o carregador do veículo.')),
              value: on,
              onChanged: s.setKeepScreenOn,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.maxBrightnessNav,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: Text(tr('Brilho de tela máximo ao navegar')),
              subtitle: FutureBuilder<bool>(
                future: Battery().isInBatterySaveMode.catchError((_) => false),
                builder: (_, snap) => Text.rich(TextSpan(children: [
                  TextSpan(text: tr(
                      'Para enxergar o mapa no sol. Vale só no UauGo enquanto navega; ao parar, volta ao brilho do celular. Atenção: com a economia de bateria ligada, o celular limita o brilho e a tela não fica no máximo.')),
                  if (snap.data == true)
                    TextSpan(
                        text: '\n${tr('⚠️ A economia de bateria está ligada agora.')}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ])),
              ),
              value: on,
              onChanged: s.setMaxBrightnessNav,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.carPlaceNames,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.directions_car_outlined),
              title: Text(tr('Nomes de lugares no mapa do carro')),
              subtitle: Text(tr('Museus, escolas, lojas e outros lugares no mapa do Android Auto. Desligado, o mapa fica mais limpo (nomes de ruas continuam).')),
              value: on,
              onChanged: s.setCarPlaceNames,
            ),
          ),
          ValueListenableBuilder<bool?>(
            valueListenable: s.lightModeChoice,
            builder: (_, choice, __) => SwitchListTile(
              secondary: const Icon(Icons.speed_outlined),
              title: Text(tr('Modo leve')),
              subtitle: Text(
                  tr('Mapa sem prédios 3D e, com o Android Auto conectado, visão 3D só no carro: o app fica mais rápido e gasta menos memória e bateria. {0}', [choice == null ? (s.lightMode ? tr('Ligado automaticamente (celular com {0} GB de RAM).', [(s.deviceMemMb / 1024).toStringAsFixed(1)]) : tr('Automático: liga em celulares com menos de 4,5 GB de RAM.')) : ''])),
              value: s.lightMode,
              onChanged: s.setLightMode,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.shareStats,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.insights),
              title: Text(tr('Compartilhar estatísticas de uso')),
              subtitle: Text(
                  tr('Anônimas: quantas pessoas usam, quais recursos e os erros do app (modelo do celular e versão), para melhorar o UauGo. Sem localização exata, nome ou e-mail.')),
              value: on,
              onChanged: s.setShareStats,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.backgroundShare,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: Text(tr('Compartilhar posição em segundo plano')),
              subtitle: Text(
                  tr('Só no comboio: o grupo continua vendo você com o app fora da tela (notificação "UauGo ativo"). Desligado, o GPS para ao sair do app. Ligar aumenta o consumo de bateria.')),
              value: on,
              onChanged: (v) {
                s.setBackgroundShare(v);
                if (!v) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      duration: const Duration(seconds: 6),
                      content: Text(tr(
                          'No comboio, o grupo deixa de ver você sempre que o UauGo sair da tela (tela bloqueada, ligação, outro app).'))));
                }
              },
            ),
          ),
          // Idioma: o do celular ou escolhido (por enquanto português e inglês).
          ValueListenableBuilder<String>(
            valueListenable: s.language,
            builder: (_, lang, __) => ListTile(
              leading: const Icon(Icons.translate),
              title: Text(tr('Idioma')),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                // 4 idiomas não cabem lado a lado (quebrava "Automá/tico"):
                // opções que descem para a linha de baixo quando precisa.
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (v, label) in [
                    ('auto', tr('Automático')),
                    ('pt', 'Português'),
                    ('en', 'English'),
                    ('es', 'Español'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: lang == v,
                      onSelected: (_) => s.setLanguage(v),
                    ),
                ]),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([s.cleanTheme, s.accent]),
            builder: (_, __) {
              final clean = s.cleanTheme.value;
              final cur = s.accent.value;
              return ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(tr('Aparência')),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(tr('Padrão'))),
                        ButtonSegment(value: true, label: Text(tr('Clean (claro)'))),
                      ],
                      selected: {clean},
                      onSelectionChanged: (v) => s.setCleanTheme(v.first),
                    ),
                    if (clean) ...[
                    const SizedBox(height: 10),
                    Text(tr('Cor dos botões')),
                    const SizedBox(height: 6),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      for (final a in AppAccent.values)
                        Tooltip(
                          message: a.label,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => s.setAccent(a),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: a.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: a == cur ? Colors.black54 : Colors.transparent,
                                    width: 3),
                              ),
                              child: a == cur
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                    ]),
                    ],
                    const SizedBox(height: 6),
                    Text(clean
                        ? tr('Tudo claro, botões em {0}. Alertas, SOS e radares mantêm as cores de segurança.', [cur.label.toLowerCase()])
                        : tr('Cores originais do UauGo.')),
                  ],
                ),
              ),
            );
            },
          ),
          // Mini player da música no mapa (precisa do acesso a notificações).
          ValueListenableBuilder<bool>(
            valueListenable: s.mediaControls,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.music_note),
              title: Text(tr('Controles de música no mapa')),
              subtitle: Text(tr('Spotify, YouTube Music, Deezer, rádio...: música, anterior, tocar/pausar e próxima sem sair do mapa. O sistema pede para liberar o "Acesso a notificações" ao UauGo; nada sai do celular.')),
              value: on,
              onChanged: (v) async {
                await s.setMediaControls(v);
                if (!v || await MediaService.instance.hasAccess() || !context.mounted) return;
                final go = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Liberar acesso')),
                    content: Text(tr('Na próxima tela, ative o UauGo em "Acesso a notificações". É assim que o sistema deixa o app ver a música que está tocando. O UauGo não lê nem guarda suas notificações.')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Abrir'))),
                    ],
                  ),
                );
                if (go == true) await MediaService.instance.openSettings();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_in_ar),
            title: Text(tr('Visão 3D')),
            subtitle: Text(tr('Só funciona com internet. Sem conexão, o app usa o mapa normal e o 3D volta sozinho.')),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: s.showTraffic,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.traffic),
              title: Text(tr('Mostrar trânsito na rota')),
              subtitle: Text(
                  tr('A linha da rota fica verde, amarela ou vermelha conforme o trânsito agora. As outras vias não mudam de cor.')),
              value: on,
              onChanged: s.setShowTraffic,
            ),
          ),
          ValueListenableBuilder<MapTheme>(
            valueListenable: s.mapTheme,
            builder: (_, t, __) => ListTile(
              leading: const Icon(Icons.dark_mode),
              title: Text(tr('Mapa noturno')),
              subtitle: Wrap(spacing: 6, children: [
                for (final m in MapTheme.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: t == m,
                    onSelected: (_) => s.setMapTheme(m),
                  ),
              ]),
            ),
          ),
          ValueListenableBuilder<BatteryMode>(
            valueListenable: s.batterySaver,
            builder: (_, b, __) => ListTile(
              leading: const Icon(Icons.battery_saver),
              title: Text(tr('Economia de bateria')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr('GPS a cada 2 s em vez de 1 s, mapa sem prédios 3D e sem trânsito. Os avisos (radar, voz, curvas) continuam.')),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in BatteryMode.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: b == m,
                        onSelected: (_) => s.setBatterySaver(m),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          section(tr('Rotas')),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
                tr('A rota é calculada pelo Google Maps. Aqui você escolhe as preferências usadas na navegação sozinho e nas novas expedições.')),
          ),
          ValueListenableBuilder<RoutePrefs>(
            valueListenable: s.route,
            builder: (_, r, __) => Column(children: [
              RadioGroup<RoutePreference>(
                groupValue: r.preference,
                onChanged: (v) => s.setRoute(r.copyWith(preference: v)),
                child: Column(children: [
                  for (final p in RoutePreference.values)
                    RadioListTile<RoutePreference>(
                      value: p,
                      title: Text(p.label),
                      subtitle: Text(p.description),
                    ),
                ]),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.toll),
                title: Text(tr('Evitar pedágios')),
                value: r.avoidTolls,
                onChanged: (v) => s.setRoute(r.copyWith(avoidTolls: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.add_road),
                title: Text(tr('Evitar rodovias')),
                subtitle: Text(tr('Prefere estradas secundárias')),
                value: r.avoidHighways,
                onChanged: (v) => s.setRoute(r.copyWith(avoidHighways: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.directions_boat),
                title: Text(tr('Evitar balsas')),
                value: r.avoidFerries,
                onChanged: (v) => s.setRoute(r.copyWith(avoidFerries: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.traffic),
                title: Text(tr('Considerar o trânsito do momento')),
                subtitle: Text(
                    tr('Chegada com o trânsito atual. Navegando sozinho, avisa trânsito intenso e troca para uma rota mais rápida (consulta a cada 5 min, só com rota traçada). Aumenta o consumo de dados e de bateria.')),
                value: r.liveTraffic,
                onChanged: (v) => s.setRoute(r.copyWith(liveTraffic: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.gpp_maybe),
                title: Text(tr('Evitar locais de risco')),
                subtitle: Text(
                    tr('A rota desvia dos pontos com muitos roubos registrados pelas secretarias de segurança e dos alertas "Área de risco / assalto" confirmados por outros usuários.')),
                value: r.avoidRisk,
                onChanged: (v) => s.setRoute(r.copyWith(avoidRisk: v)),
              ),
            ]),
          ),
          section(tr('Avisos de radar e polícia')),
          ValueListenableBuilder<AlertPrefs>(
            valueListenable: s.alerts,
            builder: (_, a, __) => Column(children: [
              _AlertPicker(
                icon: Icons.camera_alt,
                title: tr('Radares (fixos e móveis)'),
                meters: a.radarMeters,
                repeats: a.radarRepeats,
                onChanged: (m, r) =>
                    s.setAlerts(a.copyWith(radarMeters: m, radarRepeats: r)),
              ),
              _AlertPicker(
                icon: Icons.local_police,
                title: tr('Polícia na pista e postos policiais'),
                meters: a.policeMeters,
                repeats: a.policeRepeats,
                onChanged: (m, r) =>
                    s.setAlerts(a.copyWith(policeMeters: m, policeRepeats: r)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.local_police_outlined),
                title: Text(tr('Avisar postos policiais rodoviários')),
                subtitle: Text(tr('PRF e polícia rodoviária estadual (OpenStreetMap), na distância acima')),
                value: a.policePosts,
                onChanged: (v) => s.setAlerts(a.copyWith(policePosts: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.speed),
                title: Text(tr('Trechos que podem ter radar móvel')),
                subtitle: Text(tr('Trechos divulgados pela PRF (lista oficial): aviso ao entrar e linha roxa no mapa')),
                value: a.mobileStretches,
                onChanged: (v) {
                  s.setAlerts(a.copyWith(mobileStretches: v));
                },
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                    tr('Radar de avanço de sinal (cruzamentos) avisa uma vez, a no máximo 300 m. Todo aviso de radar fala a velocidade.'),
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          section(tr('Outros avisos')),
          ValueListenableBuilder<AlertPrefs>(
            valueListenable: s.alerts,
            builder: (_, a, __) => Column(children: [
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(tr('Lombadas e faixas elevadas')),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 6, children: [
                      for (final m in AlertMode.values)
                        ChoiceChip(
                          label: Text(m.label),
                          selected: a.bumps == m,
                          onSelected: (_) => s.setAlerts(a.copyWith(bumps: m)),
                        ),
                    ]),
                    Text(
                        tr('Opcional: as lombadas do estado só são baixadas se você ligar o aviso.'),
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.traffic),
                title: Text(tr('Semáforos')),
                subtitle: Text(
                    tr('Mostra os semáforos no mapa e a voz diz "No semáforo, vire à direita". Opcional: os semáforos do estado só são baixados se você ligar.')),
                value: a.signals,
                onChanged: (v) => s.setAlerts(a.copyWith(signals: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.trending_down),
                title: Text(tr('Velocidade reduzida à frente')),
                subtitle: Text(
                    tr('"Velocidade reduzida para 60 em 300 metros"')),
                value: a.reducedSpeed,
                onChanged: (v) => s.setAlerts(a.copyWith(reducedSpeed: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.umbrella),
                title: Text(tr('Chuva à frente')),
                subtitle: Text(
                    tr('Com rota traçada, confere a previsão a cada 5 min, a cada 10 km pela rota (até 50 km à frente; Open-Meteo). Aumenta o consumo de dados e de bateria.')),
                value: a.rain,
                onChanged: (v) => s.setAlerts(a.copyWith(rain: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.flag_circle),
                title: Text(tr('Metade do trajeto: na estrada')),
                subtitle: Text(tr('Avisa quando chegar a 50% da viagem (viagens de 40 km ou mais)')),
                value: a.halfway,
                onChanged: (v) => s.setAlerts(a.copyWith(halfway: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.location_city),
                title: Text(tr('Metade do trajeto: na cidade')),
                subtitle: Text(tr('Também em viagens curtas (menos de 40 km)')),
                value: a.halfwayCity,
                onChanged: (v) => s.setAlerts(a.copyWith(halfwayCity: v)),
              ),
            ]),
          ),
          section(tr('Usar sem internet')),
          ListTile(
            leading: const Icon(Icons.download_for_offline),
            title: Text(tr('Baixar dados dos estados da viagem')),
            subtitle: Text(
                tr('Limites de velocidade, lombadas e postos policiais ficam no celular. Radares já são baixados para o Brasil todo.')),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _OfflineScreen())),
          ),
          section(tr('Voz')),
          ValueListenableBuilder<bool>(
            valueListenable: voice.alertsOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.campaign),
              title: Text(tr('Avisos falados')),
              subtitle: Text(
                  tr('Radares, perigos na pista, SOS do grupo e paradas')),
              value: on,
              onChanged: voice.setAlerts,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(tr('Voz por tipo de aviso')),
            subtitle: Text(tr('Escolha quais avisos são falados. Os outros aparecem só na tela, com vibração.')),
            onTap: () => _pickVoiceKinds(context),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: voice.narrationOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.turn_right),
              title: Text(tr('Narração das curvas na navegação')),
              value: on,
              onChanged: voice.setNarration,
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: voice.voiceName,
            builder: (ctx, name, __) => ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: Text(tr('Voz')),
              subtitle: Text(name == null
                  ? tr('Automática. Toque para ouvir e escolher outra (feminina ou masculina).')
                  : OfflineVoice.byKey(name) != null
                      ? tr('{0} (voz do UauGo)', [OfflineVoice.byKey(name)!.label])
                      : voiceLabel(name)),
              onTap: () => _pickVoice(ctx),
            ),
          ),
          if (VoiceCommandService.supported) ...[
            section(tr('Acessibilidade')),
            const _VoiceCommandsTile(),
          ],
          // Só para a administração da plataforma (HelpAITech).
          FutureBuilder<bool>(
            future: ClubService.instance.isPlatformAdmin(),
            builder: (_, snap) => snap.data != true
                ? const SizedBox.shrink()
                : Column(children: [
                    section(tr('Administração')),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings),
                      title: Text(tr('Administração UauGo')),
                      subtitle: Text(
                          tr('Cadastrar clubes e gerar códigos e convites (QR code)')),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AdminScreen())),
                    ),
                  ]),
          ),
          section(tr('Sobre')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr('Sobre o UauGo')),
            subtitle: Text(tr('Desenvolvido por HelpAITech · créditos')),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          ListTile(
            leading: Icon(Icons.gavel),
            title: Text(tr('Termos de Uso')),
            subtitle: Text(tr('Versão {0}', [TermsService.version])),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsScreen())),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Política de Privacidade')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TermsScreen.privacy())),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

/// Comandos de voz (opcional): liga/desliga, baixa o modelo de voz na
/// primeira vez e mostra a lista de comandos.
class _VoiceCommandsTile extends StatefulWidget {
  const _VoiceCommandsTile();

  @override
  State<_VoiceCommandsTile> createState() => _VoiceCommandsTileState();
}

/// Estado: ligando (download) ou não.
class _VoiceCommandsTileState extends State<_VoiceCommandsTile> {
  final _svc = VoiceCommandService.instance;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (!on) {
      await _svc.disable();
      return;
    }
    setState(() => _busy = true);
    final error = await _svc.enable();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error ??
            tr('Comandos de voz ligados. Funcionam com o mapa aberto na tela.'))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = voiceAlertWords.keys.join(', ');
    return ValueListenableBuilder<bool>(
      valueListenable: _svc.enabled,
      builder: (_, on, __) => Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.mic),
          title: Text(tr('Comandos de voz (mãos livres)')),
          subtitle: Text(
              tr('Para quem está de luva: marque alertas e responda às perguntas falando, sem tocar na tela. O reconhecimento é feito no próprio celular: o áudio não sai do aparelho.')),
          value: on,
          onChanged: _busy ? null : _toggle,
        ),
        if (_busy && Platform.isAndroid)
          ValueListenableBuilder<double>(
            valueListenable: _svc.progress,
            builder: (_, p, __) => Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Baixando o reconhecimento de voz (~31 MB, só uma vez)…'),
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: p > 0 ? p : null),
              ]),
            ),
          ),
        if (on)
          Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              tr('Diga "{0}" e o alerta: {1}.\nExemplo: "{2}, radar". Para desfazer: "{3}, cancelar". Quando o app perguntar "ainda está lá?", responda "sim" ou "não".\nLocais salvos: "{4}, ir para casa" ou "... para o trabalho".\nPara achar algo no caminho: "{5}, procurar posto" (também restaurante, restaurante barato, lanche, café, padaria, pousada, hotel, oficina, pneu, farmácia, hospital, banco, mercado).\nFunciona com o mapa aberto na tela (use "Manter a tela ligada").', [voiceWakeDisplay, words, voiceWakeDisplay, voiceWakeDisplay, voiceWakeDisplay, voiceWakeDisplay]),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (on)
          ValueListenableBuilder<bool>(
            valueListenable: _svc.helmetMic,
            builder: (_, helmet, __) => SwitchListTile(
              secondary: const Icon(Icons.headset_mic),
              title: Text(tr('Microfone do comunicador do capacete')),
              subtitle: Text(tr('Ouve pelo comunicador Bluetooth, com o microfone sempre aberto. Enquanto ligado, a música no comunicador fica com qualidade de ligação. Sem comunicador conectado, usa o microfone do celular.')),
              value: helmet,
              onChanged: _svc.setHelmetMic,
            ),
          ),
        if (on)
          ValueListenableBuilder<bool>(
            valueListenable: _svc.routeByVoice,
            builder: (_, route, __) => SwitchListTile(
              secondary: const Icon(Icons.record_voice_over),
              title: Text(tr('Pesquisa de trajeto por voz')),
              subtitle: Text(
                  tr('Diga "{0}, ir para", espere o bipe e fale o destino. Usa o reconhecimento do próprio celular quando ele oferece; senão, o do Google (precisa de internet e o áudio dessa frase vai para o Google).', [voiceWakeDisplay])),
              value: route,
              onChanged: _svc.setRouteByVoice,
            ),
          ),
      ]),
    );
  }
}
