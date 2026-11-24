/// Lingkup aplikasi: menyediakan preferensi, klien API, pemutar, dan
/// pengendali tab ke seluruh pohon widget tanpa melewatkannya berulang kali.
library;

import 'package:flutter/widgets.dart';

import '../data/local_database.dart';
import '../data/settings_store.dart';
import '../data/sonora_api.dart';
import '../data/youtube_auth_service.dart';
import '../data/youtube_session.dart';
import '../data/youtube_music_service.dart';
import 'player/player_controller.dart';

/// Indeks tab bilah navigasi bawah.
abstract final class AppTabs {
  static const int home = 0;
  static const int search = 1;
  static const int library = 2;
  static const int settings = 3;
  static const int count = 4;
}

/// Pengendali tab: dipakai agar layar dapat meminta perpindahan tab
/// (mis. CTA "Buka Pengaturan" saat proxy belum dikonfigurasi).
class AppTabController extends ChangeNotifier {
  AppTabController({int initialIndex = AppTabs.home}) : _index = initialIndex;

  int _index;

  int get index => _index;

  void goTo(int index) {
    if (index < 0 || index >= AppTabs.count || index == _index) return;
    _index = index;
    notifyListeners();
  }
}

/// Menyediakan dependensi aplikasi ke subtree UI.
class SonoraScope extends InheritedWidget {
  /// Fallback sesi anonim untuk pemanggil yang tidak menyuntikkan [auth]
  /// (mis. harness pengujian) — berstatus belum masuk tanpa efek jaringan.
  static final YoutubeAuthService _anonymousAuth = YoutubeAuthService(
    store: InMemorySessionStore(),
  );

  /// Membuat scope. [auth] boleh ditiadakan; scope memakai sesi anonim.
  SonoraScope({
    super.key,
    required this.settings,
    required this.api,
    required this.ytService,
    YoutubeAuthService? auth,
    required this.player,
    required this.tabs,
    this.database,
    required super.child,
  }) : auth = auth ?? _anonymousAuth;

  final SettingsStore settings;
  final SonoraApi api;
  final YouTubeMusicService ytService;

  /// Layanan sesi YouTube Music; tidak pernah `null` agar layar dapat
  /// membaca status login tanpa pemeriksaan tambahan.
  final YoutubeAuthService auth;
  final PlayerController player;
  final AppTabController tabs;

  /// Basis data lokal opsional (riwayat pencarian, favorit). `null` bila
  /// perangkat tidak mendukung SQLite — fitur terkait turun dengan anggun.
  final LocalDatabase? database;

  static SonoraScope of(BuildContext context) {
    final SonoraScope? scope =
        context.dependOnInheritedWidgetOfExactType<SonoraScope>();
    assert(scope != null, 'SonoraScope.of() dipanggil di luar SonoraScope.');
    return scope!;
  }

  @override
  bool updateShouldNotify(SonoraScope oldWidget) => false;
}
