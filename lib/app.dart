import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/home.dart';
import 'features/onboarding.dart';
import 'features/quick_categorize.dart';
import 'features/reminders.dart';
import 'features/settings.dart';
import 'features/shell.dart';
import 'features/transactions.dart';
import 'providers.dart';

class HamrahApp extends ConsumerStatefulWidget {
  const HamrahApp({super.key, required this.onboarded});

  final bool onboarded;

  @override
  ConsumerState<HamrahApp> createState() => _HamrahAppState();
}

class _HamrahAppState extends ConsumerState<HamrahApp> with WidgetsBindingObserver {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.onboarded ? '/' : '/onboarding',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellPage(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/transactions', builder: (context, state) => TransactionsPage(status: state.uri.queryParameters['status'])),
          GoRoute(path: '/reminders', builder: (context, state) => const RemindersPage()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
        ],
      ),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
      GoRoute(
        path: '/quick',
        builder: (context, state) => QuickCategorizePage(txUid: state.uri.queryParameters['tx'] ?? ''),
      ),
      GoRoute(path: '/unrecognized', builder: (context, state) => const UnrecognizedPage()),
      GoRoute(path: '/diagnostics', builder: (context, state) => const DiagnosticsPage()),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final coordinator = ref.read(syncCoordinatorProvider);
    await coordinator.run(force: true);
    final bridge = ref.read(bridgeProvider);
    bridge.onRoute((route) {
      if (mounted) _router.go(route);
    });
    final pending = await bridge.consumePendingRoute();
    if (mounted && pending != null && pending.isNotEmpty && pending != '/') {
      _router.go(pending);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(syncCoordinatorProvider).run());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'همراه',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      routerConfig: _router,
    );
  }
}

class RecoveryApp extends StatelessWidget {
  const RecoveryApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 16),
                  Text('پایگاه داده باز نشد', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'کلید رمزنگاری این دستگاه در دسترس نیست؛ برای جلوگیری از آسیب به داده‌ها، برنامه هیچ تغییری ایجاد نکرد. '
                    'اگر نسخهٔ پشتیبان دارید یا دستگاه را بازیابی کرده‌اید، با پشتیبانی تماس بگیرید.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
