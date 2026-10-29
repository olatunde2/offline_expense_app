import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secure_hive_store.dart';

class SyncService {
  SyncService(this._store, {http.Client? client})
    : _client = client ?? http.Client();

  final SecureHiveStore _store;
  final http.Client _client;

  Future<bool> syncPending() async {
    final endpoint = _store.syncEndpoint;
    if (endpoint == null || endpoint.isEmpty) return false;

    for (final operation in _store.queuedOperations) {
      final operationId = operation['operation_id'] as String;
      final response = await _client
          .post(
            Uri.parse('$endpoint/expenses/sync'),
            headers: {
              'Content-Type': 'application/json',
              'Idempotency-Key': operationId,
            },
            body: jsonEncode({
              'client_id': await _store.clientId(),
              'operation': operation,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Sync endpoint returned HTTP ${response.statusCode}',
          Uri.parse('$endpoint/expenses/sync'),
        );
      }
      await _store.acknowledgeOperation(operation);
    }
    return true;
  }

  void close() => _client.close();
}
