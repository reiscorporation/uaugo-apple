// ============================================================================
// profile_screen.dart — "Minha moto / Meu carro"
//
// O que faz: Foto, marca, modelo, tipo (moto ou carro), cor do marcador e
//   consumo (km/l e preço do litro) para estimar gastos.
// Quem usa: HomeScreen e MapScreen.
// Onde mexer: Consumo: AppSettings.fuel.
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/costs.dart';
import '../models/bike.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

/// "Minha moto": foto, marca, modelo, estilo e cor do marcador.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// Estado da tela: veículo, foto nova, consumo.
class _ProfileScreenState extends State<ProfileScreen> {
  BikeProfile _bike = const BikeProfile();
  final _modelCtrl = TextEditingController();
  File? _newPhoto;
  bool _loading = true;
  bool _saving = false;

  // Consumo e gastos (opcional; fica só no celular).
  late bool _fuelOn = AppSettings.instance.fuel.value.enabled;
  final _kmlCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final f = AppSettings.instance.fuel.value;
    if (f.kmPerLiter > 0) _kmlCtrl.text = formatDecimal(f.kmPerLiter);
    if (f.pricePerLiter > 0) _priceCtrl.text = formatDecimal(f.pricePerLiter, 2);
    ProfileService.load().then((b) {
      if (!mounted) return;
      setState(() {
        _bike = b;
        _modelCtrl.text = b.model;
        _loading = false;
      });
    });
  }

  /// Escolhe uma foto (câmera ou galeria), já reduzida para 600 px.
  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (x != null) setState(() => _newPhoto = File(x.path));
  }

  /// Salva o veículo (envia a foto nova e apaga a antiga) e o consumo.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await ProfileService.load();
      var url = _bike.photoUrl;
      if (_newPhoto != null) {
        final uid = await AuthService.ensureSignedIn();
        url = await ProfileService.uploadPhoto(uid, _newPhoto!,
            oldUrl: saved.photoUrl);
      } else if (url == null && saved.photoUrl != null) {
        // Usuário removeu a foto.
        await ProfileService.deletePhoto(saved.photoUrl);
      }
      final p = _bike.copyWith(
        model: _modelCtrl.text.trim(),
        photoUrl: url,
        clearPhoto: url == null,
      );
      await ProfileService.save(p);
      await AppSettings.instance.setFuel(FuelPrefs(
        enabled: _fuelOn,
        kmPerLiter: parseDecimal(_kmlCtrl.text) ?? 0,
        pricePerLiter: parseDecimal(_priceCtrl.text) ?? 0,
      ));
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ImageProvider? get _photo {
    if (_newPhoto != null) return FileImage(_newPhoto!);
    if (_bike.photoUrl != null) return NetworkImage(_bike.photoUrl!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(_bike.color);
    final photo = _photo;

    return Scaffold(
      appBar: AppBar(
          title: Text(_bike.style.isCar ? 'Meu carro' : 'Minha moto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white, width: 4),
                    image: photo == null
                        ? null
                        : DecorationImage(image: photo, fit: BoxFit.cover),
                  ),
                  child: photo == null
                      ? Icon(_bike.style.icon,
                          size: 80,
                          color: color.computeLuminance() > 0.6
                              ? Colors.black
                              : Colors.white)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Câmera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeria'),
                  ),
                  if (photo != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _newPhoto = null;
                        _bike = _bike.copyWith(clearPhoto: true);
                      }),
                      child: const Text('Remover foto'),
                    ),
                ],
              ),
              Text(
                'Use uma foto do seu veículo. Ela aparece no mapa para todo o comboio.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Text('Marca', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in _bike.style.isCar ? carBrands : bikeBrands)
                  ChoiceChip(
                    label: Text(b),
                    selected: _bike.brand == b,
                    onSelected: (_) =>
                        setState(() => _bike = _bike.copyWith(brand: b)),
                  ),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: _modelCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                  hintText: 'Versys 650',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tipo (moto ou carro; vira o ícone quando não há foto)',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in BikeStyle.values)
                  ChoiceChip(
                    avatar: Icon(s.icon, size: 18),
                    label: Text(s.label),
                    selected: _bike.style == s,
                    onSelected: (_) =>
                        setState(() => _bike = _bike.copyWith(style: s)),
                  ),
              ]),
              const SizedBox(height: 20),
              Text('Cor do marcador', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in bikeColors)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _bike = _bike.copyWith(color: c)),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _bike.color == c
                              ? theme.colorScheme.primary
                              : Colors.white24,
                          width: _bike.color == c ? 4 : 1,
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),
              // Consumo e gastos (opcional).
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Calcular consumo e gastos da viagem'),
                subtitle: const Text(
                    'Mostra o combustível estimado de cada rota e permite '
                    'registrar abastecimentos e gastos. Fica só no seu celular.'),
                value: _fuelOn,
                onChanged: (v) => setState(() => _fuelOn = v),
              ),
              if (_fuelOn)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _kmlCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Consumo médio',
                        suffixText: 'km/l',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço do litro',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ]),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Salvar'),
              ),
            ]),
    );
  }
}
