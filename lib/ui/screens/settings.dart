/// Layar Settings: alamat proxy yang dapat disunting, uji koneksi, dan simpan.
/// Menyimpan endpoint yang valid menghentikan audio lama dan menyegarkan feed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/audio_cache_service.dart';
import '../../data/music_models.dart';
import '../../data/settings_store.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _TestState { idle, testing, ok, fail }

/// Preset equalizer siap pakai (nilai dB per band, rendah ke tinggi).
enum _EqPreset {
  flat('Flat', <double>[0, 0, 0, 0, 0]),
  bass('Bass Boost', <double>[6, 4, 2, 0, 0]),
  vocal('Vokal', <double>[-2, 0, 3, 3, 0]),
  treble('Treble', <double>[0, 0, 2, 4, 6]);

  const _EqPreset(this.label, this.gains);
  final String label;
  final List<double> gains;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  SettingsStore? _settings;
  bool _addonEnabled = false;
  bool _saving = false;
  String? _saveError;
  _TestState _test = _TestState.idle;
  String? _testMessage;
  int _cacheBytes = 0;
  bool _clearingCache = false;
  AndroidEqualizerParameters? _eqParams;
  List<double> _eqGains = const <double>[0, 0, 0, 0, 0];
  bool _clearingHistory = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final int bytes = await AudioCacheService.getCacheSizeBytes();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    await AudioCacheService.clearCache();
    await _loadCacheSize();
    if (!mounted) return;
    setState(() => _clearingCache = false);
    showSonoraSnack(context, 'Cache audio berhasil dibersihkan.', success: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SettingsStore settings = SonoraScope.of(context).settings;
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = settings..addListener(_onSettingsChanged);
      _addonEnabled = settings.isConfigured;
      _controller.text =
          settings.isConfigured ? settings.proxyBase : settings.proxyDraft;
    }
    _loadEqualizerIfNeeded();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // Sinkronkan bidang bila nilai berubah dari tempat lain.
    final String current = _settings!.proxyBase;
    if (current.isNotEmpty) {
      _addonEnabled = true;
      if (_controller.text.trim() != current) {
        _controller.text = current;
      }
    }
    setState(() {});
  }

  Future<void> _onToggleAddon(bool enabled) async {
    final SonoraScope scope = SonoraScope.of(context);
    setState(() {
      _addonEnabled = enabled;
      _saveError = null;
      _test = _TestState.idle;
      _testMessage = null;
    });

    if (!enabled) {
      final String text = _controller.text.trim();
      if (scope.settings.isConfigured) {
        await scope.settings.setProxyBase('');
        await scope.player.stop();
        if (mounted) {
          showSonoraSnack(
            context,
            'Add-on dinonaktifkan. Mode mandiri aktif.',
            success: true,
          );
        }
      }
      if (text.isNotEmpty) {
        await scope.settings.setProxyDraft(text);
      }
    } else {
      if (_controller.text.trim().isEmpty &&
          scope.settings.proxyDraft.isNotEmpty) {
        _controller.text = scope.settings.proxyDraft;
      }
    }
  }

  Future<void> _save() async {
    final SonoraScope scope = SonoraScope.of(context);
    final String previous = scope.settings.proxyBase;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await scope.settings.setProxyBase(_controller.text);
      if (!mounted) return;
      final bool changed = scope.settings.proxyBase != previous;
      if (changed) {
        // Endpoint berganti: hentikan audio dari host lama sebelum feed baru.
        await scope.player.stop();
        if (!mounted) return;
        showSonoraSnack(context, 'Endpoint tersimpan. Feed disegarkan.', success: true);
      } else {
        showSonoraSnack(context, 'Endpoint tersimpan.', success: true);
      }
      setState(() {
        _test = _TestState.idle;
        _testMessage = null;
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _saveError = error.message?.toString() ?? 'URL proxy tidak valid.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = 'Gagal menyimpan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final SonoraScope scope = SonoraScope.of(context);
    final String base = _controller.text.trim();
    if (base.isEmpty) {
      setState(() {
        _test = _TestState.fail;
        _testMessage = 'Isi alamat proxy terlebih dahulu.';
      });
      return;
    }
    setState(() {
      _test = _TestState.testing;
      _testMessage = null;
    });
    try {
      await scope.api.checkConnection(base);
      if (!mounted) return;
      setState(() {
        _test = _TestState.ok;
        _testMessage = base.replaceAll(RegExp(r'/+$'), '');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _test = _TestState.fail;
        _testMessage = error is SonoraApiException ? error.message : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraScope scope = SonoraScope.of(context);
    final int limitMb = scope.settings.cacheLimitMb;
    final String limitLabel = limitMb >= 1024 ? '1 GB' : '$limitMb MB';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: kSpaceXxl),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceLg, kSpaceLg, kSpaceSm),
              child: Text('Pengaturan', style: context.texts.displaySmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(kSpaceLg),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(kRadiusLg),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.extension_rounded,
                              size: 22,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: kSpaceSm),
                            Text('Add-ons', style: context.texts.titleMedium),
                          ],
                        ),
                        const SizedBox(height: kSpaceXs),
                        Text(
                          'Ekstensi dan integrasi server tambahan. '
                          'Bila dinonaktifkan, seluruh pemutaran dan pencarian berjalan '
                          '100% mandiri langsung dari perangkat.',
                          style: context.texts.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: kSpaceMd),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(kRadiusMd),
                          ),
                          // ListTile melukis latar & ink ripple pada Material
                          // terdekat; tanpa Material ini, latar Container
                          // menyembunyikan efeknya (assert debug Flutter).
                          child: Material(
                            color: Colors.transparent,
                            child: SwitchListTile.adaptive(
                              value: _addonEnabled,
                              onChanged: _saving ? null : _onToggleAddon,
                              activeTrackColor: scheme.primary,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: kSpaceMd,
                                vertical: kSpaceXs,
                              ),
                              title: Text(
                                'Sonora Node Proxy',
                                style: context.texts.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _addonEnabled
                                    ? (scope.settings.isConfigured
                                        ? 'Aktif — terhubung ke proxy pribadi'
                                        : 'Menunggu simpan alamat URL')
                                    : 'Dinonaktifkan (Mode Mandiri Aktif)',
                                style: context.texts.bodySmall?.copyWith(
                                  color: _addonEnabled
                                      ? (scope.settings.isConfigured
                                          ? context.sonora.success
                                          : scheme.onSurfaceVariant)
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_addonEnabled) ...<Widget>[
                          const SizedBox(height: kSpaceLg),
                          Text(
                            'Alamat Server Proxy',
                            style: context.texts.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: kSpaceXs),
                          TextField(
                            controller: _controller,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(),
                            onChanged: (_) {
                              if (_test != _TestState.idle) {
                                setState(() {
                                  _test = _TestState.idle;
                                  _testMessage = null;
                                });
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'https://host:8787',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                          ),
                          if (_saveError != null) ...<Widget>[
                            const SizedBox(height: kSpaceSm),
                            _Banner(
                              icon: Icons.error_outline_rounded,
                              color: scheme.error,
                              background: scheme.errorContainer,
                              text: _saveError!,
                            ),
                          ],
                          const SizedBox(height: kSpaceLg),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2.2),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: const Text('Simpan'),
                                ),
                              ),
                              const SizedBox(width: kSpaceMd),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _test == _TestState.testing ? null : _testConnection,
                                  icon: const Icon(Icons.wifi_tethering_rounded),
                                  label: const Text('Tes koneksi'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: kSpaceMd),
                          _testStatus(scope),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: kSpaceXl),
                  _audioSection(context, scope),
                  const SizedBox(height: kSpaceXl),
                  _themeSection(context, scope),
                  const SizedBox(height: kSpaceXl),
                  _settingsCard(
                    context,
                    icon: Icons.cached_rounded,
                    title: 'Penyimpanan & Cache Audio',
                    subtitle:
                        'Berkas stream audio yang telah di-cache ke memori perangkat agar dapat diputar mulus tanpa jeda buffer.',
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Batas penyimpanan otomatis',
                              style: context.texts.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                          DropdownButton<int>(
                            value: scope.settings.cacheLimitMb,
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem<int>(value: 250, child: Text('250 MB')),
                              DropdownMenuItem<int>(value: 500, child: Text('500 MB')),
                              DropdownMenuItem<int>(value: 1024, child: Text('1 GB')),
                              DropdownMenuItem<int>(value: 0, child: Text('Tanpa batas')),
                            ],
                            onChanged: (int? value) {
                              if (value == null) return;
                              _applySetting(
                                  () => scope.settings.setCacheLimitMb(value));
                              if (value > 0) {
                                unawaited(AudioCacheService.pruneCache(
                                    maxBytes: value * 1024 * 1024));
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: kSpaceMd),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  limitMb > 0
                                      ? 'Penggunaan Cache (Batas: $limitLabel)'
                                      : 'Penggunaan Cache',
                                  style: context.texts.labelSmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  limitMb > 0
                                      ? '${AudioCacheService.formatBytes(_cacheBytes)} / $limitLabel'
                                      : AudioCacheService.formatBytes(_cacheBytes),
                                  style: context.texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _clearingCache ? null : _clearCache,
                            icon: _clearingCache
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.delete_outline_rounded, size: 20),
                            label: const Text('Bersihkan'),
                          ),
                        ],
                      ),
                      if (limitMb > 0) ...<Widget>[
                        const SizedBox(height: kSpaceMd),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(kRadiusSm),
                          child: LinearProgressIndicator(
                            value: (_cacheBytes / (limitMb * 1024 * 1024))
                                .clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              (_cacheBytes / (limitMb * 1024 * 1024)) > 0.9
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: kSpaceXs),
                      Text(
                        limitMb > 0
                            ? 'Pembersihan otomatis LRU memangkas cache saat mendekati batas.'
                            : 'Tanpa batas: pembersihan otomatis LRU dinonaktifkan.',
                        style: context.texts.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: kSpaceXl),
                  _historyCard(context, scope),
                  const SizedBox(height: kSpaceXl),
                  Text('Status', style: context.texts.titleMedium),
                  const SizedBox(height: kSpaceSm),
                  _StatusRow(
                    label: 'Add-on Proxy',
                    value: scope.settings.isConfigured
                        ? scope.settings.proxyBase
                        : 'Dinonaktifkan (Mode Mandiri)',
                    ok: scope.settings.isConfigured,
                  ),
                  const SizedBox(height: kSpaceXl),
                  Text(
                    'Direct Stream YouTube (Bitrate Tertinggi) • Mode Mandiri',
                    style: context.texts.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      backgroundColor: scheme.surface,
    );
  }

  // ---------------------------------------------------------------------------
  // Seksi pengaturan: audio, tampilan, riwayat
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpaceSm),
      child: Text(text, style: context.texts.titleMedium),
    );
  }

  Widget _settingsCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final ColorScheme scheme = context.scheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kSpaceLg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: kSpaceSm),
              Text(title, style: context.texts.titleMedium),
            ],
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            subtitle,
            style: context.texts.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: kSpaceMd),
          ...children,
        ],
      ),
    );
  }

  Future<void> _applySetting(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showSonoraSnack(context, 'Gagal menyimpan pengaturan: $error');
    }
  }

  void _loadEqualizerIfNeeded() {
    if (_eqParams != null) return;
    final AndroidEqualizer? equalizer = SonoraScope.of(context).player.equalizer;
    if (equalizer == null) return;
    equalizer.parameters.then((AndroidEqualizerParameters parameters) {
      if (!mounted) return;
      setState(() {
        _eqParams = parameters;
        final List<int> stored = SonoraScope.of(context).settings.equalizerBands;
        _eqGains = List<double>.generate(
          parameters.bands.length,
          (int i) => i < stored.length ? stored[i].toDouble() : 0,
        );
      });
    });
  }

  Widget _audioSection(BuildContext context, SonoraScope scope) {
    final SettingsStore settings = scope.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionLabel('Audio'),
        _settingsCard(
          context,
          icon: Icons.graphic_eq_rounded,
          title: 'Kualitas Audio',
          subtitle:
              'Terbaik memilih bitrate tertinggi, Otomatis memprioritaskan '
              'AAC/M4A agar seeking presisi, Hemat memilih bitrate terendah.',
          children: <Widget>[
            SegmentedButton<AudioQuality>(
              segments: const <ButtonSegment<AudioQuality>>[
                ButtonSegment<AudioQuality>(
                    value: AudioQuality.best, label: Text('Terbaik')),
                ButtonSegment<AudioQuality>(
                    value: AudioQuality.auto, label: Text('Otomatis')),
                ButtonSegment<AudioQuality>(
                    value: AudioQuality.hemat, label: Text('Hemat')),
              ],
              selected: <AudioQuality>{settings.audioQuality},
              onSelectionChanged: (Set<AudioQuality> selected) {
                _applySetting(() => settings.setAudioQuality(selected.first));
              },
            ),
          ],
        ),
        _autoplayCard(context, scope),
        const SizedBox(height: kSpaceMd),
        _equalizerCard(context, scope),
      ],
    );
  }

  Widget _autoplayCard(BuildContext context, SonoraScope scope) {
    final SettingsStore settings = scope.settings;
    final ColorScheme scheme = context.scheme;
    return _settingsCard(
      context,
      icon: Icons.auto_awesome_rounded,
      title: 'Putar otomatis',
      subtitle:
          'Setelah lagu terakhir, saran radio YouTube otomatis mengisi antrean.',
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              value: settings.autoplayEnabled,
              onChanged: (bool value) {
                _applySetting(() => settings.setAutoplayEnabled(value));
              },
              activeTrackColor: scheme.primary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: kSpaceMd,
                vertical: kSpaceXs,
              ),
              title: Text(
                'Aktifkan putar otomatis',
                style: context.texts.titleSmall,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _equalizerCard(BuildContext context, SonoraScope scope) {
    final SettingsStore settings = scope.settings;
    final AndroidEqualizer? equalizer = scope.player.equalizer;
    final ColorScheme scheme = context.scheme;
    return _settingsCard(
      context,
      icon: Icons.equalizer_rounded,
      title: 'Equalizer',
      subtitle: equalizer == null
          ? 'Equalizer hanya tersedia di perangkat Android.'
          : 'Setel gain tiap band (dB) atau pakai preset cepat.',
      children: <Widget>[
        if (equalizer != null) ...<Widget>[
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(kRadiusMd),
            ),
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                value: settings.equalizerEnabled,
                onChanged: (bool value) {
                  unawaited(equalizer.setEnabled(value));
                  _applySetting(() => settings.setEqualizerEnabled(value));
                },
                activeTrackColor: scheme.primary,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: kSpaceMd,
                  vertical: kSpaceXs,
                ),
                title: Text('Aktifkan equalizer', style: context.texts.titleSmall),
              ),
            ),
          ),
          const SizedBox(height: kSpaceMd),
          Wrap(
            spacing: kSpaceXs,
            runSpacing: kSpaceXs,
            children: <Widget>[
              for (final _EqPreset preset in _EqPreset.values)
                ActionChip(
                  label: Text(preset.label),
                  onPressed: () =>
                      _applyEqualizerPreset(equalizer, settings, preset),
                ),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          if (_eqParams == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kSpaceSm),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            for (var i = 0; i < _eqGains.length; i++)
              _equalizerBandSlider(equalizer, settings, i),
        ],
      ],
    );
  }

  Widget _equalizerBandSlider(
    AndroidEqualizer equalizer,
    SettingsStore settings,
    int index,
  ) {
    final ColorScheme scheme = context.scheme;
    final AndroidEqualizerParameters parameters = _eqParams!;
    final AndroidEqualizerBand band = parameters.bands[index];
    final double min = parameters.minDecibels.clamp(-15.0, 0.0).toDouble();
    final double max = parameters.maxDecibels.clamp(0.0, 15.0).toDouble();
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            _formatHz(band.centerFrequency),
            style: context.texts.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Slider(
            value: _eqGains[index].clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            label: '${_eqGains[index].toStringAsFixed(1)} dB',
            onChanged: (double value) {
              setState(() => _eqGains[index] = value);
              band.setGain(value);
            },
            onChangeEnd: (double value) {
              final List<int> gains =
                  _eqGains.map((double v) => v.round()).toList();
              _applySetting(() => settings.setEqualizerBands(gains));
            },
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${_eqGains[index].toStringAsFixed(1)} dB',
            textAlign: TextAlign.end,
            style: context.texts.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  void _applyEqualizerPreset(
    AndroidEqualizer equalizer,
    SettingsStore settings,
    _EqPreset preset,
  ) {
    final List<double> gains = preset.gains;
    setState(() => _eqGains = List<double>.from(gains));
    final List<AndroidEqualizerBand> bands =
        _eqParams?.bands ?? const <AndroidEqualizerBand>[];
    for (var i = 0; i < bands.length && i < gains.length; i++) {
      bands[i].setGain(gains[i]);
    }
    _applySetting(
      () => settings.setEqualizerBands(gains.map((double v) => v.round()).toList()),
    );
  }

  String _formatHz(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)} kHz';
    return '${hz.round()} Hz';
  }

  Widget _themeSection(BuildContext context, SonoraScope scope) {
    final SettingsStore settings = scope.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionLabel('Tampilan'),
        _settingsCard(
          context,
          icon: Icons.dark_mode_rounded,
          title: 'Mode Tema',
          subtitle: 'Ikuti tema sistem, atau paksa gelap/terang secara manual.',
          children: <Widget>[
            SegmentedButton<AppThemeMode>(
              segments: const <ButtonSegment<AppThemeMode>>[
                ButtonSegment<AppThemeMode>(
                    value: AppThemeMode.sistem, label: Text('Sistem')),
                ButtonSegment<AppThemeMode>(
                    value: AppThemeMode.gelap, label: Text('Gelap')),
                ButtonSegment<AppThemeMode>(
                    value: AppThemeMode.terang, label: Text('Terang')),
              ],
              selected: <AppThemeMode>{settings.themeMode},
              onSelectionChanged: (Set<AppThemeMode> selected) {
                _applySetting(() => settings.setThemeMode(selected.first));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _historyCard(BuildContext context, SonoraScope scope) {
    return _settingsCard(
      context,
      icon: Icons.history_rounded,
      title: 'Riwayat',
      subtitle:
          'Bersihkan riwayat pencarian dan riwayat putar yang tersimpan di perangkat.',
      children: <Widget>[
        OutlinedButton.icon(
          onPressed:
              _clearingHistory ? null : () => _confirmClearHistory(scope),
          icon: _clearingHistory
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_sweep_rounded, size: 20),
          label: const Text('Bersihkan riwayat'),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory(SonoraScope scope) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Bersihkan riwayat?'),
        content: const Text(
          'Seluruh riwayat pencarian dan riwayat putar akan dihapus dari '
          'perangkat. Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearingHistory = true);
    try {
      await scope.database?.clearSearchHistory();
      await scope.database?.clearPlaybackHistory();
      if (!mounted) return;
      showSonoraSnack(context, 'Riwayat berhasil dibersihkan.', success: true);
    } catch (_) {
      if (!mounted) return;
      showSonoraSnack(context, 'Gagal membersihkan riwayat.');
    } finally {
      if (mounted) setState(() => _clearingHistory = false);
    }
  }

  Widget _testStatus(SonoraScope scope) {
    final ColorScheme scheme = context.scheme;
    switch (_test) {
      case _TestState.idle:
        return const SizedBox.shrink();
      case _TestState.testing:
        return Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: kSpaceSm),
            Text('Menguji koneksi…', style: context.texts.bodyMedium),
          ],
        );
      case _TestState.ok:
        return _Banner(
          icon: Icons.check_circle_rounded,
          color: context.sonora.success,
          background: scheme.surfaceContainerHigh,
          text: 'Terhubung — ${_testMessage ?? ''}',
        );
      case _TestState.fail:
        return _Banner(
          icon: Icons.error_outline_rounded,
          color: scheme.error,
          background: scheme.surfaceContainerHigh,
          text: 'Gagal: ${_testMessage ?? 'Tidak dapat menghubungi proxy.'}',
        );
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: kSpaceSm),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 20,
          color: ok ? context.sonora.success : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: kSpaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: context.texts.labelLarge),
              Text(
                value,
                style: context.texts.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
