/// Layar Settings: alamat proxy yang dapat disunting, uji koneksi, dan simpan.
/// Menyimpan endpoint yang valid menghentikan audio lama dan menyegarkan feed.
library;

import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _TestState { idle, testing, ok, fail }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  SettingsStore? _settings;
  bool _saving = false;
  String? _saveError;
  _TestState _test = _TestState.idle;
  String? _testMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SettingsStore settings = SonoraScope.of(context).settings;
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = settings..addListener(_onSettingsChanged);
      _controller.text = settings.proxyBase;
    }
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
    if (_controller.text.trim() != current) {
      _controller.text = current;
    }
    setState(() {});
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
                  Text('Server proxy', style: context.texts.titleMedium),
                  const SizedBox(height: kSpaceXs),
                  Text(
                    'Alamat proxy Sonora milikmu (http/https lengkap). '
                    'Audio dan feed diambil melalui alamat ini.',
                    style: context.texts.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: kSpaceLg),
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
                  const SizedBox(height: kSpaceXl),
                  const Divider(),
                  const SizedBox(height: kSpaceLg),
                  Text('Status', style: context.texts.titleMedium),
                  const SizedBox(height: kSpaceSm),
                  _StatusRow(
                    label: 'Endpoint',
                    value: scope.settings.isConfigured
                        ? scope.settings.proxyBase
                        : 'Belum diatur',
                    ok: scope.settings.isConfigured,
                  ),
                  const SizedBox(height: kSpaceXl),
                  Text(
                    'Sonora • proxy stateless • pemutaran melalui relay /stream',
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
