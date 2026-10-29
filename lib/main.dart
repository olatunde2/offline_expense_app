import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'data/expense.dart';
import 'data/secure_hive_store.dart';
import 'data/sync_service.dart';
import 'state/expense_controller.dart';
import 'ui/home_screen.dart';

const _syncTaskName = 'sync-expenses';
const _periodicTaskName =
    'dev.example.offline_expense_app.periodic-expense-sync';
final _workmanager = Workmanager();

@pragma('vm:entry-point')
void callbackDispatcher() {
  _workmanager.executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    SecureHiveStore? store;
    SyncService? syncService;
    try {
      store = await SecureHiveStore.open();
      syncService = SyncService(store);
      await syncService.syncPending();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Background expense sync failed: $error\n$stackTrace');
      return false;
    } finally {
      syncService?.close();
      await store?.close();
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Hive.registerAdapter(ExpenseAdapter());
  final store = await SecureHiveStore.open();
  final syncService = SyncService(store);

  if (const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  }.contains(defaultTargetPlatform)) {
    await _workmanager.initialize(callbackDispatcher);
    await _workmanager.registerPeriodicTask(
      _periodicTaskName,
      _syncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        expenseStoreProvider.overrideWithValue(store),
        syncServiceProvider.overrideWithValue(syncService),
      ],
      child: const OfflineExpenseApp(),
    ),
  );
}

class OfflineExpenseApp extends ConsumerStatefulWidget {
  const OfflineExpenseApp({super.key});

  @override
  ConsumerState<OfflineExpenseApp> createState() => _OfflineExpenseAppState();
}

class _OfflineExpenseAppState extends ConsumerState<OfflineExpenseApp> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(ref.read(expenseControllerProvider.notifier).syncNow());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(expenseControllerProvider.notifier).syncNow());
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Ledger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF146C5A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F4),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
