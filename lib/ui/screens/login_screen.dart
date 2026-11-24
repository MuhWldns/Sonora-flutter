/// Layar masuk YouTube Music: WebView login Google yang menangkap sesi
/// (cookie + ytcfg) dan menyerahkannya ke [YoutubeAuthService] lewat
/// [SonoraScope]. Penangkapan dilakukan manual lewat tombol "Gunakan Akun"
/// setelah pengguna diarahkan ke halaman YouTube Music — tanpa polling
/// otomatis, sehingga tidak ada notifikasi gagal yang muncul sendiri.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// URL login Google yang diarahkan kembali ke YouTube Music.
const String _kLoginUrl = 'https://accounts.google.com/ServiceLogin'
    '?ltmpl=music&service=youtube&prompt=select_account'
    '&continue=https%3A%2F%2Fmusic.youtube.com%2F';

/// Host tujuan: halaman Music yang memuat ytcfg sesi.
const String _kMusicHost = 'music.youtube.com';

/// Probe ytcfg: membaca nilai sesi tanpa mencatat isi halaman.
/// Dibungkus IIFE karena `evaluateJavascript` Android menolak `return`
/// di level atas skrip.
const String _kYtcfgProbe = '''
(function(){
var get=function(k){try{var v=window.ytcfg.get(k);return v===undefined||v===null?'':String(v);}catch(e){return '';}}
;return JSON.stringify({loggedIn:get('LOGGED_IN'),pageId:get('DELEGATED_SESSION_ID'),dataSyncId:get('DATASYNC_ID'),authUser:get('SESSION_INDEX'),visitorData:get('VISITOR_DATA'),clientVersion:get('INNERTUBE_CLIENT_VERSION')});
})()
''';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final WebViewController _controller;
  bool _capturing = false;

  /// True bila WebView sedang berada di halaman music.youtube.com —
  /// syarat tombol "Gunakan Akun" aktif.
  bool _onMusicHost = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: _onPageFinished,
        ),
      )
      ..loadRequest(Uri.parse(_kLoginUrl));
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    _updateMusicHost(Uri.tryParse(request.url));
    // Biarkan semua navigasi berjalan; penangkapan sesi dilakukan manual
    // lewat tombol "Gunakan Akun".
    return NavigationDecision.navigate;
  }

  void _onPageFinished(String url) {
    _updateMusicHost(Uri.tryParse(url));
  }

  /// Memperbarui penanda halaman Music; hanya membangun ulang saat berubah.
  void _updateMusicHost(Uri? uri) {
    final bool onMusic = uri != null && uri.host.contains(_kMusicHost);
    if (mounted && onMusic != _onMusicHost) {
      setState(() => _onMusicHost = onMusic);
    }
  }

  /// Satu percobaan penangkapan sesi: cookie + probe ytcfg sekali jalan,
  /// lalu diserahkan ke [YoutubeAuthService]. Gagal cukup diulang dengan
  /// menekan tombol lagi — tanpa percobaan otomatis.
  Future<void> _captureSession() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      // 1) Cookie untuk domain Music (jangan pernah dicetak/log).
      final cookies = await WebviewCookieManager().getCookies(
        'https://$_kMusicHost',
      );
      final String cookieHeader =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');

      // 2) Probe ytcfg dari halaman yang sudah termuat.
      final Object result = await _controller.runJavaScriptReturningResult(
        _kYtcfgProbe,
      );
      final Map<String, dynamic> cfg = _parseProbe(result);

      // 3) Serahkan ke service; service yang memutuskan validitas sesi.
      final String pageId = cfg['pageId'] as String? ?? '';
      if (!mounted) return;
      final bool ok = await SonoraScope.of(context).auth.capture(
            cookie: cookieHeader,
            pageId: pageId.isEmpty ? null : pageId,
            dataSyncId: cfg['dataSyncId'] as String? ?? '',
            authUser: cfg['authUser'] as String? ?? '',
            visitorData: cfg['visitorData'] as String? ?? '',
            clientVersion: cfg['clientVersion'] as String? ?? '',
          );
      if (!mounted) return;
      if (ok) {
        showSonoraSnack(context, 'Berhasil masuk', success: true);
        Navigator.of(context).pop();
      } else {
        // Sesi ditolak: tetap di halaman; pengguna bisa menekan tombol lagi.
        showSonoraSnack(context, 'Sesi tidak valid, coba lagi');
      }
    } catch (_) {
      if (!mounted) return;
      showSonoraSnack(context, 'Sesi tidak valid, coba lagi');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// `runJavaScriptReturningResult` dapat mengembalikan String JSON,
  /// bool, atau num — normalisasi menjadi peta yang aman.
  Map<String, dynamic> _parseProbe(Object result) {
    try {
      final String raw = result is String ? result : result.toString();
      final String trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == 'null') {
        return const <String, dynamic>{};
      }
      final Object? decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masuk ke YouTube Music'),
        leading: IconButton(
          tooltip: 'Tutup',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      backgroundColor: scheme.surface,
      body: Column(
        children: <Widget>[
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          if (_capturing) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Masuk ke Google, lalu tekan Gunakan Akun setelah '
                    'diarahkan ke YouTube Music.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _onMusicHost && !_capturing ? _captureSession : null,
                      child: const Text('Gunakan Akun'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
