import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_state.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/registration_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/screens/detail_screens.dart';
import '../../features/splash/splash_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable();
  ref.listen(authNotifierProvider, (previous, next) {
    refreshListenable.refresh();
  });

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.matchedLocation;
      final isEntryRoute = location == '/' || location == '/login';

      if (authState.status == AuthStatus.loading) {
        return location == '/' ? null : '/';
      }

      if (!authState.isAuthenticated) {
        return isEntryRoute ? null : '/login';
      }

      if (!authState.user!.isCustomerLinked) {
        return location == '/register' || location == '/verify'
            ? null
            : '/register';
      }

      if (isEntryRoute || location == '/register' || location == '/verify') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/verify',
        builder: (context, state) => const RegistrationScreen(verifyOtp: true),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(initialTab: 0),
      ),
      GoRoute(
        path: '/billing',
        builder: (context, state) => const HomeScreen(initialTab: 1),
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const HomeScreen(initialTab: 2),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const HomeScreen(initialTab: 3),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const HomeScreen(initialTab: 4),
      ),
      GoRoute(
        path: '/invoice/:id',
        builder: (context, state) =>
            InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/payment/:id',
        builder: (context, state) =>
            PaymentScreen(invoiceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/subscription/upgrade',
        builder: (context, state) => const UpgradeScreen(),
      ),
      GoRoute(
        path: '/tickets/new',
        builder: (context, state) => const NewTicketScreen(),
      ),
      GoRoute(
        path: '/tickets/:id',
        builder: (context, state) =>
            TicketDetailScreen(ticketId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/transactions',
        builder: (context, state) => const TransactionsScreen(),
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (context, state) =>
            TransactionDetailScreen(transactionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(path: '/help', builder: (context, state) => const HelpScreen()),
      GoRoute(
        path: '/help/:topic',
        builder: (context, state) =>
            HelpTopicScreen(topic: state.pathParameters['topic']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/legal/:document',
        builder: (context, state) =>
            LegalScreen(document: state.pathParameters['document']!),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refreshListenable.dispose();
  });
  return router;
});

class _RouterRefreshListenable extends ChangeNotifier {
  void refresh() => notifyListeners();
}
