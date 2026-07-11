import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/email_otp_screen.dart';
import '../../features/transactions/add_transaction_screen.dart';
import '../../features/transactions/transaction_list_screen.dart';
import '../../features/transactions/transaction_detail_screen.dart';
import '../../features/transactions/csv_import_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../shared/models/models.dart';
import '../../features/dashboard/merchant_breakdown_screen.dart';
import '../../features/savings/savings_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../shared/widgets/main_shell.dart';
import '../../features/balance/balance_check_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isAuthenticated && !isAuthRoute) return '/auth/email_otp';
      if (isAuthenticated && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      // ── Auth routes ─────────────────────────────────────────
      GoRoute(
        path: '/auth/email_otp',
        name: 'emailAuth',
        builder: (context, state) => const EmailOtpScreen(),
      ),

      // ── Main shell (bottom nav) ──────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/merchant-breakdown/:type',
            name: 'merchantBreakdown',
            builder: (context, state) {
              final typeString = state.pathParameters['type']!;
              final type = typeString == 'debit' ? TransactionType.debit : TransactionType.credit;
              return MerchantBreakdownScreen(type: type);
            },
          ),
          GoRoute(
            path: '/transactions',
            name: 'transactions',
            builder: (context, state) => const TransactionListScreen(),
            routes: [
              GoRoute(
                path: 'add',
                name: 'addTransaction',
                builder: (context, state) => const AddTransactionScreen(),
              ),
              GoRoute(
                path: ':txId',
                name: 'transactionDetail',
                builder: (context, state) {
                  final txId = state.pathParameters['txId']!;
                  return TransactionDetailScreen(txId: txId);
                },
              ),
              GoRoute(
                path: 'import/csv',
                name: 'csvImport',
                builder: (context, state) => const CsvImportScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/savings',
            name: 'savings',
            builder: (context, state) => const SavingsScreen(),
          ),
          GoRoute(
            path: '/categories',
            name: 'categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/balance',
            name: 'balance',
            builder: (context, state) => const BalanceCheckScreen(),
          ),
        ],
      ),

      // ── Profile Settings ────────────────────────────────────
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),

      // ── Redirect root ───────────────────────────────────────
      GoRoute(
        path: '/',
        redirect: (_, __) => '/dashboard',
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: Text(
          'Page not found: ${state.error}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
});
