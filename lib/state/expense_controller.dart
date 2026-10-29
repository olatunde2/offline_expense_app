import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../data/expense.dart';
import '../data/secure_hive_store.dart';
import '../data/sync_service.dart';

final expenseStoreProvider = Provider<SecureHiveStore>(
  (ref) => throw StateError('Expense store was not initialized'),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => throw StateError('Sync service was not initialized'),
);

final expenseControllerProvider =
    NotifierProvider<ExpenseController, ExpenseState>(ExpenseController.new);

class ExpenseState {
  const ExpenseState({
    required this.expenses,
    required this.pendingCount,
    required this.syncing,
    required this.syncEndpoint,
    this.error,
  });

  final List<Expense> expenses;
  final int pendingCount;
  final bool syncing;
  final String? syncEndpoint;
  final String? error;

  ExpenseState copyWith({
    List<Expense>? expenses,
    int? pendingCount,
    bool? syncing,
    String? syncEndpoint,
    String? error,
    bool clearError = false,
  }) => ExpenseState(
    expenses: expenses ?? this.expenses,
    pendingCount: pendingCount ?? this.pendingCount,
    syncing: syncing ?? this.syncing,
    syncEndpoint: syncEndpoint ?? this.syncEndpoint,
    error: clearError ? null : error ?? this.error,
  );
}

class ExpenseController extends Notifier<ExpenseState> {
  late SecureHiveStore _store;
  late SyncService _syncService;

  @override
  ExpenseState build() {
    _store = ref.read(expenseStoreProvider);
    _syncService = ref.read(syncServiceProvider);
    ref.onDispose(_syncService.close);
    return ExpenseState(
      expenses: _store.expenses,
      pendingCount: _store.pendingCount,
      syncing: false,
      syncEndpoint: _store.syncEndpoint,
    );
  }

  Future<void> addExpense({
    required int amountCents,
    required String category,
    required String note,
    required DateTime occurredAt,
  }) async {
    final expense = Expense(
      id: const Uuid().v4(),
      amountCents: amountCents,
      category: category,
      note: note.trim(),
      occurredAt: occurredAt,
      isSynced: false,
    );
    await _store.addExpense(expense);
    state = state.copyWith(
      expenses: _store.expenses,
      pendingCount: _store.pendingCount,
      clearError: true,
    );
    await _scheduleSync();
  }

  Future<void> deleteExpense(Expense expense) async {
    await _store.deleteExpense(expense);
    state = state.copyWith(
      expenses: _store.expenses,
      pendingCount: _store.pendingCount,
      clearError: true,
    );
    await _scheduleSync();
  }

  Future<void> setSyncEndpoint(String endpoint) async {
    await _store.setSyncEndpoint(endpoint);
    state = state.copyWith(syncEndpoint: _store.syncEndpoint, clearError: true);
    await _scheduleSync();
  }

  Future<void> syncNow() async {
    if (state.syncing ||
        state.pendingCount == 0 ||
        state.syncEndpoint == null) {
      return;
    }
    state = state.copyWith(syncing: true, clearError: true);
    try {
      await _syncService.syncPending();
      state = state.copyWith(
        expenses: _store.expenses,
        pendingCount: _store.pendingCount,
        syncing: false,
      );
    } catch (error) {
      state = state.copyWith(
        pendingCount: _store.pendingCount,
        syncing: false,
        error: error.toString(),
      );
    }
  }

  Future<void> _scheduleSync() async {
    if (state.syncEndpoint == null) return;
    await Workmanager().registerOneOffTask(
      'expense-sync-${DateTime.now().microsecondsSinceEpoch}',
      'sync-expenses',
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }
}
