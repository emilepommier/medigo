import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:medigo/nav/navigation_provider.dart';
import 'package:medigo/auth/auth_state.dart';
import 'theme.dart';
import 'dart:async';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/screens/recherche_screen.dart';
import 'package:medigo/screens/pharmacie_screen.dart';
import 'package:medigo/screens/reglages_screen.dart';
import 'package:medigo/screens/login_screen.dart';
import 'package:medigo/screens/signup_screen.dart';
import 'package:medigo/screens/drug_detail_screen.dart';
import 'package:medigo/screens/presentation_detail_screen.dart';
import 'package:medigo/screens/family_options_screen.dart';
import 'package:medigo/screens/manual_drug_form_screen.dart';
import 'package:medigo/screens/custom_item_detail_screen.dart';
import 'package:medigo/screens/advanced_settings_screen.dart';
import 'package:medigo/screens/about_screen.dart';
import 'package:medigo/services/notification_service.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:medigo/services/family_state.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Main entry point for the application
///
/// This sets up:
/// - Supabase initialization
/// - Provider state management (ThemeProvider, CounterProvider)
/// - go_router navigation
/// - Material 3 theming with light/dark modes
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure French date symbols are available (needed on web for month names)
  try {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
  } catch (e) {
    debugPrint('Failed to initialize intl locale fr_FR: $e');
  }

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize local notifications (expiry alerts)
  await NotificationService.initialize();
  // Optionally request permissions if enabled
  try { if (await NotificationService.isEnabled()) { await NotificationService.requestPermissions(); } } catch (_) {}

  // Initialize the app
  runApp(const MyApp());
}

final _authNotifier = AuthStateNotifier();


// Horizontal slide page used for push-style navigations (not bottom tabs)
CustomTransitionPage<T> _slidePage<T>({required Widget child}) {
  return CustomTransitionPage<T>(
    opaque: true,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // Incoming page slides from right on push, returns to right on pop
      final slideIn = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved);
      // Slight parallax for outgoing page
      final slideOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.05, 0)).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic),
      );
      return Stack(children: [
        SlideTransition(position: slideOut, child: const SizedBox()),
        SlideTransition(position: slideIn, child: child),
      ]);
    },
  );
}

final _router = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final loggedIn = _authNotifier.isLoggedIn;
    final loggingIn =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    if (!loggedIn && !loggingIn) {
      return '/login';
    }
    if (loggedIn && loggingIn) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: AppShell(),
      ),
    ),
    GoRoute(
      path: '/settings/advanced',
      name: 'advanced_settings',
      pageBuilder: (context, state) => _slidePage(child: const AdvancedSettingsScreen()),
    ),
    GoRoute(
      path: '/settings/about',
      name: 'about',
      pageBuilder: (context, state) => _slidePage(child: const AboutScreen()),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      pageBuilder: (context, state) => _slidePage(
        child: Scaffold(
          appBar: AppBar(title: const Text('Recherche')),
          body: const RechercheScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/drug/:cis',
      name: 'drug_detail',
      pageBuilder: (context, state) {
        final cisStr = state.pathParameters['cis'];
        final cis = int.tryParse(cisStr ?? '');
        if (cis == null) {
          return const NoTransitionPage(child: Scaffold(body: Center(child: Text('CIS invalide'))));
        }
        return _slidePage(child: DrugDetailScreen(cis: cis));
      },
    ),
    GoRoute(
      path: '/presentation/:cip13',
      name: 'presentation_detail',
      pageBuilder: (context, state) {
        final cip = state.pathParameters['cip13'];
        if (cip == null || cip.isEmpty) {
          return const NoTransitionPage(child: Scaffold(body: Center(child: Text('CIP invalide'))));
        }
        return _slidePage(child: PresentationDetailScreen(cip13: cip));
      },
    ),
    GoRoute(
      path: '/settings/family',
      name: 'family_options',
      pageBuilder: (context, state) => _slidePage(child: const FamilyOptionsScreen()),
    ),
    GoRoute(
      path: '/pharmacie/manual_add',
      name: 'manual_add',
      pageBuilder: (context, state) => _slidePage(child: const ManualDrugFormScreen()),
    ),
    GoRoute(
      path: '/custom',
      name: 'custom_detail',
      pageBuilder: (context, state) {
        final key = state.uri.queryParameters['key'];
        if (key == null || key.isEmpty) {
          return const NoTransitionPage(child: Scaffold(body: Center(child: Text('Élément introuvable'))));
        }
        return _slidePage(child: CustomItemDetailScreen(customKey: key));
      },
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiProvider wraps the app to provide state to all widgets
    // When adding new providers, include them in the providers list below
    return MultiProvider(
      providers: [
        // Counter provider for managing counter state
        ChangeNotifierProvider(
          create: (_) => CounterProvider(),
        ),
        // Bottom tab navigation provider
        ChangeNotifierProvider(create: (_) => NavigationProvider()),

        // Family provider keeps family data ready before Settings opens
        ChangeNotifierProvider(create: (_) => FamilyState()..preload()),

        // TODO (agent): Add new providers here as you extend the app
        // Example:
        // ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: MaterialApp.router(
        title: 'Dreamflow Starter',
        debugShowCheckedModeBanner: false,

        // Theme configuration
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,

        // Router configuration
        routerConfig: _router,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<PharmacieScreenState> _pharmacieKey =
      GlobalKey<PharmacieScreenState>();
  bool _fabOpen = false;
  StreamSubscription<String>? _notifSub;
  // Expiry badge state for the navigation bar
  int _expiringCountNav = 0;
  RealtimeChannel? _entriesChannel;
  StreamSubscription<void>? _storeChangesSub;

  Future<void> _refreshAll() async {
    try {
      final idx = context.read<NavigationProvider>().index;
      if (idx == 0) {
        await _ensurePharmacieThen((s) => s.refreshAll());
        await _updateExpiringBadge();
      } else if (idx == 1) {
        // Refresh settings-related data
        try { await context.read<FamilyState>().refresh(); } catch (e) { debugPrint('Family refresh failed: $e'); }
        // No explicit state change needed; widgets watch FamilyState
      }
    } catch (e) {
      debugPrint('Home pull-to-refresh failed: $e');
    }
  }


  @override
  void dispose() {
    _notifSub?.cancel();
    _storeChangesSub?.cancel();
    if (_entriesChannel != null) {
      try { SupabaseConfig.client.removeChannel(_entriesChannel!); } catch (_) {}
      _entriesChannel = null;
    }
    super.dispose();
  }


  Future<void> _updateExpiringBadge() async {
    try {
      // Load aggregate items, then inspect their entries to compute count
      final items = await PharmacieStore.load();
      if (items.isEmpty) {
        if (mounted) setState(() => _expiringCountNav = 0);
        return;
      }
      final lists = await Future.wait(items.map((it) => PharmacieStore.loadEntries(it.cip13)));
      final now = DateTime.now();
      final nKey = now.year * 100 + now.month;
      int total = 0;
      for (final entries in lists) {
        for (final e in entries) {
          final ex = e.expiresAt;
          if (ex == null) continue;
          final eKey = ex.year * 100 + ex.month;
          if (eKey <= nKey) total++;
        }
      }
      if (mounted) setState(() => _expiringCountNav = total);
    } catch (e) {
      debugPrint('Failed to update nav expiry badge: $e');
    }
  }

  Future<void> _ensurePharmacieThen(Future<void> Function(PharmacieScreenState s) task) async {
    if (_pharmacieKey.currentState != null) {
      await task(_pharmacieKey.currentState!);
      return;
    }
    try {
      context.read<NavigationProvider>().setIndex(0);
      // Allow a frame for PharmacieScreen to mount
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_pharmacieKey.currentState != null) {
        await task(_pharmacieKey.currentState!);
      } else {
        // Try again on next microtask if still null
        await Future.microtask(() async {
          final st = _pharmacieKey.currentState;
          if (st != null) {
            await task(st);
          } else {
            debugPrint('PharmacieScreen state not ready to run task');
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to run Pharmacie task: $e');
    }
  }

  Widget _buildFabMenu(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(splashFactory: InkRipple.splashFactory),
      child: FloatingActionButton(
        heroTag: 'fab_main',
        enableFeedback: true,
        elevation: 6,
        highlightElevation: 8,
        hoverElevation: 8,
        focusElevation: 8,
        onPressed: () => setState(() => _fabOpen = !_fabOpen),
        tooltip: _fabOpen ? 'Fermer le menu' : 'Ajouter',
        shape: const CircleBorder(),
        child: AnimatedRotation(
          turns: _fabOpen ? 0.125 : 0.0, // 45° when open
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final idx = nav.index;
    final pages = [
      PharmacieScreen(key: _pharmacieKey),
      const ReglagesScreen(),
    ];
    final titles = ['Pharmacie', 'Réglages'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[idx]),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _refreshAll,
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: pages[idx],
            ),
            if (_fabOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _fabOpen = false),
                  child: Container(
                    // Subtle scrim behind the FAB menu
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                ),
              ),
            // Overlay action menu positioned above the center-docked FAB
            if (_fabOpen)
              Positioned(
                left: 0,
                right: 0,
                // Tighter gap above the FAB
                bottom: 52 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Scan action (topmost)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        offset: _fabOpen ? Offset.zero : const Offset(0, 0.1),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _fabOpen ? 1 : 0,
                          child: Builder(
                            builder: (context) => FloatingActionButton.extended(
                              heroTag: 'fab_scan',
                              enableFeedback: true,
                              elevation: 4,
                              highlightElevation: 6,
                              hoverElevation: 6,
                              focusElevation: 6,
                              onPressed: () async {
                                setState(() => _fabOpen = false);
                                await _ensurePharmacieThen((s) => s.scanAndAdd());
                              },
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              shape: const StadiumBorder(),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scanner un code'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Manual add action (middle)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        offset: _fabOpen ? Offset.zero : const Offset(0, 0.12),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _fabOpen ? 1 : 0,
                          child: Builder(
                            builder: (context) => FloatingActionButton.extended(
                              heroTag: 'fab_add_manual',
                              enableFeedback: true,
                              elevation: 4,
                              highlightElevation: 6,
                              hoverElevation: 6,
                              focusElevation: 6,
                              onPressed: () async {
                                setState(() => _fabOpen = false);
                                if (mounted) context.pushNamed('manual_add');
                              },
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              shape: const StadiumBorder(),
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Ajout manuel'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Search action (closest to the FAB)
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: _fabOpen ? Offset.zero : const Offset(0, 0.14),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _fabOpen ? 1 : 0,
                        child: Builder(
                          builder: (context) => FloatingActionButton.extended(
                            heroTag: 'fab_search',
                            enableFeedback: true,
                            elevation: 4,
                            highlightElevation: 6,
                            hoverElevation: 6,
                            focusElevation: 6,
                            onPressed: () async {
                              setState(() => _fabOpen = false);
                              if (mounted) context.pushNamed('search');
                            },
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            shape: const StadiumBorder(),
                            icon: const Icon(Icons.search),
                            label: const Text('Recherche'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildFabMenu(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (_fabOpen) setState(() => _fabOpen = false);
                    context.read<NavigationProvider>().setIndex(0);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _expiringCountNav > 0
                          ? Badge(
                              label: Text('$_expiringCountNav'),
                              child: Icon(
                                Icons.local_pharmacy,
                                color: idx == 0 ? Theme.of(context).colorScheme.primary : null,
                              ),
                            )
                          : Icon(
                              Icons.local_pharmacy,
                              color: idx == 0 ? Theme.of(context).colorScheme.primary : null,
                            ),
                      const SizedBox(height: 2),
                      Text(
                        'Pharmacie',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: idx == 0 ? Theme.of(context).colorScheme.primary : null,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 64),
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (_fabOpen) setState(() => _fabOpen = false);
                    context.read<NavigationProvider>().setIndex(1);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.settings,
                        color: idx == 1 ? Theme.of(context).colorScheme.primary : null,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Réglages',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: idx == 1 ? Theme.of(context).colorScheme.primary : null,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CounterProvider extends ChangeNotifier {
  int _counter = 0;

  /// Current counter value
  int get counter => _counter;

  /// Increment the counter and notify listeners
  void increment() {
    _counter++;
    notifyListeners();
  }

  /// Reset the counter to zero
  void reset() {
    if (_counter != 0) {
      _counter = 0;
      notifyListeners();
    }
  }
}
