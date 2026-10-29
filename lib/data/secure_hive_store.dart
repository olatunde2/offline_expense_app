import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'expense.dart';

class SecureHiveStore {
  SecureHiveStore._(this._expenses, this._queue, this._settings);

  static const _secureStorage = FlutterSecureStorage();
  static const _encryptionKeyName = 'expense_database_key_v1';
  static const _clientIdName = 'expense_sync_client_id_v1';
  static const _endpointSetting = 'sync_endpoint';

  final Box<Expense> _expenses;
  final Box<String> _queue;
  final Box<String> _settings;

  static Future<SecureHiveStore> open() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ExpenseAdapter());
    }
    final key = await _loadOrCreateSecret(_encryptionKeyName, 32);
    final cipher = HiveAesCipher(key);
    final expenses = await Hive.openBox<Expense>(
      'expenses_v1',
      encryptionCipher: cipher,
    );
    final queue = await Hive.openBox<String>(
      'sync_queue_v1',
      encryptionCipher: cipher,
    );
    final settings = await Hive.openBox<String>(
      'private_settings_v1',
      encryptionCipher: cipher,
    );
    return SecureHiveStore._(expenses, queue, settings);
  }

  static Future<List<int>> _loadOrCreateSecret(String name, int length) async {
    final stored = await _secureStorage.read(key: name);
    if (stored != null) {
      final key = base64Url.decode(base64Url.normalize(stored));
      if (key.length != length) {
        throw StateError('Stored local encryption key has an invalid length');
      }
      return key;
    }

    final random = Random.secure();
    final key = List<int>.generate(length, (_) => random.nextInt(256));
    await _secureStorage.write(key: name, value: base64UrlEncode(key));
    return key;
  }

  List<Expense> get expenses {
    final result = _expenses.values.toList()
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    return result;
  }

  int get pendingCount => _queue.length;

  String? get syncEndpoint => _settings.get(_endpointSetting);

  Future<String> clientId() async => _loadOrCreateString(
    _clientIdName,
    () => _secureStorage.read(key: _clientIdName),
  );

  Future<String> _loadOrCreateString(
    String name,
    Future<String?> Function() read,
  ) async {
    final current = await read();
    if (current != null && current.isNotEmpty) return current;
    final value = base64UrlEncode(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    );
    await _secureStorage.write(key: name, value: value);
    return value;
  }

  Future<void> setSyncEndpoint(String endpoint) async {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      await _settings.delete(_endpointSetting);
      return;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('Enter a valid HTTP or HTTPS URL');
    }
    if (uri.scheme == 'http' &&
        uri.host != '10.0.2.2' &&
        uri.host != 'localhost') {
      throw const FormatException('Use HTTPS for remote sync servers');
    }
    await _settings.put(
      _endpointSetting,
      trimmed.replaceFirst(RegExp(r'/+$'), ''),
    );
  }

  Future<void> addExpense(Expense expense) async {
    await _expenses.put(expense.id, expense);
    await _enqueue({
      'operation_id': expense.id,
      'type': 'upsert',
      'expense': expense.toJson(),
    });
  }

  Future<void> deleteExpense(Expense expense) async {
    await _expenses.delete(expense.id);
    await _enqueue({
      'operation_id': '${expense.id}:delete',
      'type': 'delete',
      'expense_id': expense.id,
    });
  }

  Future<void> _enqueue(Map<String, Object> operation) =>
      _queue.put(operation['operation_id']! as String, jsonEncode(operation));

  List<Map<String, dynamic>> get queuedOperations => _queue.values
      .map((encoded) => jsonDecode(encoded) as Map<String, dynamic>)
      .toList(growable: false);

  Future<void> acknowledgeOperation(Map<String, dynamic> operation) async {
    final operationId = operation['operation_id'] as String;
    if (operation['type'] == 'upsert') {
      final expenseId = operation['expense']['id'] as String;
      final expense = _expenses.get(expenseId);
      if (expense != null) {
        await _expenses.put(expenseId, expense.copyWith(isSynced: true));
      }
    }
    await _queue.delete(operationId);
  }

  Future<void> close() async {
    await _expenses.close();
    await _queue.close();
    await _settings.close();
  }
}
