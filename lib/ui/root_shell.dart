/// Cangkang aplikasi: tiga tab (Beranda, Cari, Pengaturan) dengan mini-player
/// yang menempel di atas bilah navigasi. Pemutar penuh dibuka dari mini-player.
library;

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'player/player_chrome.dart';
import 'screens/home.dart';
import 'screens/search.dart';
import 'screens/settings.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppTabController? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppTabController tabs = SonoraScope.of(context).tabs;
    if (!identical(tabs, _tabs)) {
      _tabs?.removeListener(_onTabChanged);
      _tabs = tabs..addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppTabController tabs = SonoraScope.of(context).tabs;
    return Scaffold(
      body: IndexedStack(
        index: tabs.index,
        children: const <Widget>[
          HomeScreen(),
          SearchScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: tabs.index,
            onDestinationSelected: tabs.goTo,
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Beranda',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search_rounded),
                label: 'Cari',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Pengaturan',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
