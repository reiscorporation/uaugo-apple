// ============================================================================
// settings_screen.dart — Configurações
//
// O que faz: Tela (sempre ligada, trânsito, mapa noturno, economia de
//   bateria), rotas, avisos (radar, polícia, lombadas, chuva, metade), voz,
//   "Usar sem internet" e Sobre.
// Quem usa: HomeScreen (engrenagem) e MapScreen (Voz → Mais configurações).
// Onde mexer: Valores e padrões: services/app_settings.dart.
// ============================================================================

import 'package:flutter/material.dart';

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
            title: Text(AuthService.displayName),
            subtitle: Text(AuthService.email),
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
  Future<void> _editEmergency(BuildContext context, (String, String)? c) async {
    final name = TextEditingController(text: c?.$1 ?? '');
    final phone = TextEditingController(text: c?.$2 ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Contato de emergência')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Nome (ex.: Ana)')),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: tr('WhatsApp com DDD'), hintText: '(16) 99999-9999'),
          ),
          const SizedBox(height: 8),
          Text(tr('Fica só no seu celular. Usado apenas quando você toca no SOS.'),
              style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          if (c != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 'apagar'), child: Text(tr('Apagar'))),
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
      if (name.text.trim().isEmpty || digits.length < 10) return;
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
          section(tr('Conta')),
          const _AccountTile(),
          section(tr('Tela')),
          ValueListenableBuilder<bool>(
            valueListenable: s.keepScreenOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.brightness_high),
              title: Text(tr('Manter a tela ligada no mapa')),
              subtitle: Text(
                  tr('A tela não apaga enquanto o mapa estiver aberto. Navegando, ela fica sempre ligada. Use com o carregador da moto.')),
              value: on,
              onChanged: s.setKeepScreenOn,
            ),
          ),
          ValueListenableBuilder<(String, String)?>(
            valueListenable: s.emergencyContact,
            builder: (ctx, c, __) => ListTile(
              leading: const Icon(Icons.contact_emergency_outlined),
              title: Text(tr('Contato de emergência')),
              subtitle: Text(c == null
                  ? tr('Ninguém cadastrado. No SOS, um toque avisa essa pessoa pelo WhatsApp com a sua localização.')
                  : tr('{0} · {1}\nNo SOS: "Avisar {2} pelo WhatsApp".', [c.$1, c.$2, c.$1])),
              isThreeLine: c != null,
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editEmergency(ctx, c),
            ),
          ),
          ValueListenableBuilder<bool?>(
            valueListenable: s.lightModeChoice,
            builder: (_, choice, __) => SwitchListTile(
              secondary: const Icon(Icons.speed_outlined),
              title: Text(tr('Modo leve')),
              subtitle: Text(
                  tr('Mapa sem prédios 3D e sem a camada de trânsito: o app fica mais rápido e gasta menos memória e bateria. {0}', [choice == null ? (s.lightMode ? tr('Ligado automaticamente (celular com {0} GB de RAM).', [(s.deviceMemMb / 1024).toStringAsFixed(1)]) : tr('Automático: liga em celulares com menos de 4,5 GB de RAM.')) : ''])),
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
              onChanged: s.setBackgroundShare,
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
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'auto', label: Text(tr('Automático'))),
                    const ButtonSegment(value: 'pt', label: Text('Português')),
                    const ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {lang},
                  onSelectionChanged: (v) => s.setLanguage(v.first),
                ),
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
          ValueListenableBuilder<bool>(
            valueListenable: s.showTraffic,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.traffic),
              title: Text(tr('Mostrar trânsito no mapa')),
              subtitle: Text(
                  tr('Vias em verde, laranja e vermelho conforme o trânsito agora (do Google, sem custo)')),
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
                    tr('Entre as rotas possíveis, escolhe a que passa longe das áreas com relatos de assalto reportadas pelos usuários (alerta "Área de risco / assalto").')),
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
                title: Text(tr('Semáforo nas curvas')),
                subtitle: Text(
                    tr('A voz diz "No semáforo, vire à direita". Opcional: os semáforos do estado só são baixados se você ligar.')),
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
                title: Text(tr('Metade do trajeto')),
                subtitle: Text(tr('Avisa quando chegar a 50% da viagem')),
                value: a.halfway,
                onChanged: (v) => s.setAlerts(a.copyWith(halfway: v)),
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
          ValueListenableBuilder<bool>(
            valueListenable: voice.narrationOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.turn_right),
              title: Text(tr('Narração das curvas na navegação')),
              value: on,
              onChanged: voice.setNarration,
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
        if (_busy)
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
