import 'package:flutter/material.dart';

import 'data/settings_store.dart';
import 'data/sonora_api.dart';
import 'playback/sonora_audio_handler.dart';
import 'ui/sonora_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Startup());
}

class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  SettingsStore? _settings;
  SonoraApi? _api;
  SonoraAudioHandler? _audio;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _failed = false);
    SettingsStore? settings;
    SonoraApi? api;
    try {
      settings = await SettingsStore.load();
      api = SonoraApi(settings);
      final audio = await SonoraAudioHandler.initialize(api);
      if (!mounted) {
        await audio.dispose();
        api.close();
        settings.dispose();
        return;
      }
      setState(() {
        _settings = settings;
        _api = api;
        _audio = audio;
      });
    } catch (_) {
      api?.close();
      settings?.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_audio != null) {
      return SonoraApp(settings: _settings!, api: _api!, audio: _audio!);
    }
    return MaterialApp(
      title: 'Sonora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF59E0B)),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_off_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text('Pemutar audio tidak dapat disiapkan.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _initialize,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}
