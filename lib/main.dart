import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:medigo/auth/auth_state.dart';
import 'theme.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/screens/recherche_screen.dart';
import 'package:medigo/screens/pharmacie_screen.dart';
import 'package:medigo/screens/reglages_screen.dart';
import 'package:medigo/screens/login_screen.dart';
import 'package:medigo/screens/signup_screen.dart';
import 'package:medigo/screens/drug_detail_screen.dart';
import 'package:medigo/screens/presentation_detail_screen.dart';
import 'package:medigo/screens/family_options_screen.dart';

/// Main entry point for the application
///
/// This sets up:
/// - Supabase initialization
/// - Provider state management (ThemeProvider, CounterProvider)
/// - go_router navigation
/// - Material 3 theming with light/dark modes
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await SupabaseConfig.initialize();
  
  // Initialize the app
  runApp(const MyApp());
}

final _authNotifier = AuthStateNotifier();

final _router = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final loggedIn = _authNotifier.isLoggedIn;
    final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';

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
      builder: (context, state) {
        final cisStr = state.pathParameters['cis'];
        final cis = int.tryParse(cisStr ?? '');
        if (cis == null) {
          return const Scaffold(
            body: Center(child: Text('CIS invalide')),
          );
        }
        return DrugDetailScreen(cis: cis);
      },
    ),
    GoRoute(
      path: '/presentation/:cip13',
      name: 'presentation_detail',
      builder: (context, state) {
        final cip = state.pathParameters['cip13'];
        if (cip == null || cip.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('CIP invalide')),
          );
        }
        return PresentationDetailScreen(cip13: cip);
      },
    ),
    GoRoute(
      path: '/settings/family',
      name: 'family_options',
      builder: (context, state) => const FamilyOptionsScreen(),
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
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const PharmacieScreen(),
      const RechercheScreen(),
      const ReglagesScreen(),
    ];
    final titles = ['Pharmacie', 'Recherche', 'Réglages'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        centerTitle: true,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: pages[_index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_pharmacy), label: 'Pharmacie'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Recherche'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Réglages'),
        ],
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
