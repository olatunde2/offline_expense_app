# Pocket Ledger

An Android/iOS Flutter expense tracker designed to keep working offline. Expenses and the pending operation queue are stored in AES-encrypted Hive boxes. The 256-bit Hive key and a stable sync client ID are stored with `FlutterSecureStorage`.

## Run

```powershell
flutter pub get
flutter run
```

Android requires an installed SDK with accepted Android licenses. iOS builds require macOS and Xcode. No remote service is required to record expenses or view the local chart.

## Use offline and sync later

1. Add expenses; they are persisted on-device before any network request.
2. Open the settings icon and configure the base URL of a sync server.
3. Pending changes are sent when connectivity returns, when requested with pull-to-refresh, and by Workmanager background jobs.

The app posts each queued change to `POST {base_url}/expenses/sync` with an `Idempotency-Key` header. Request body:

```json
{
  "client_id": "stable-device-id",
  "operation": {
    "operation_id": "stable-operation-id",
    "type": "upsert",
    "expense": {
      "id": "expense-id",
      "amount_cents": 1299,
      "category": "Food",
      "note": "Lunch",
      "occurred_at": "2026-10-23T12:00:00.000Z"
    }
  }
}
```

Deletion operations use `"type": "delete"` and `"expense_id"` instead of `"expense"`. Any HTTP 2xx response acknowledges that operation locally; non-2xx responses and network errors leave the operation queued for retry. The server must deduplicate by `Idempotency-Key`, authenticate the caller, and apply operations idempotently. Use HTTPS for remote endpoints; HTTP is accepted only for `localhost` and Android emulator host `10.0.2.2`.

## Storage and platform behavior

- Money is stored as integer cents, not floating-point values.
- Hive expense, settings, and sync-queue boxes are encrypted with a randomly generated 256-bit key. The key is stored in platform secure storage and is not written into the database.
- Android backup is disabled to avoid restoring encrypted Hive files without their device-bound key.
- Workmanager is registered with a connected-network constraint. Android/iOS control background scheduling; periodic work is not guaranteed to run at an exact time, and iOS may defer or omit background execution. Foreground connectivity changes also trigger sync.
- The interface shows queued changes and sync errors. If no server URL is configured, the app remains local-only.
- The sample uses USD formatting. Add locale/currency selection, authenticated sync, server conflict resolution, key rotation, and account/device recovery before production use. Losing the secure-storage key makes the encrypted local data unreadable.

## Checks

```powershell
flutter analyze
flutter test
flutter build apk --debug
```
