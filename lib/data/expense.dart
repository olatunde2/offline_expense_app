import 'package:hive/hive.dart';

class Expense {
  const Expense({
    required this.id,
    required this.amountCents,
    required this.category,
    required this.note,
    required this.occurredAt,
    required this.isSynced,
  });

  final String id;
  final int amountCents;
  final String category;
  final String note;
  final DateTime occurredAt;
  final bool isSynced;

  Expense copyWith({bool? isSynced}) => Expense(
    id: id,
    amountCents: amountCents,
    category: category,
    note: note,
    occurredAt: occurredAt,
    isSynced: isSynced ?? this.isSynced,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'amount_cents': amountCents,
    'category': category,
    'note': note,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  int get typeId => 1;

  @override
  Expense read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var index = 0; index < count; index++) {
      fields[reader.readByte()] = reader.read();
    }
    return Expense(
      id: fields[0] as String,
      amountCents: fields[1] as int,
      category: fields[2] as String,
      note: fields[3] as String,
      occurredAt: DateTime.parse(fields[4] as String),
      isSynced: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.amountCents)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.note)
      ..writeByte(4)
      ..write(obj.occurredAt.toIso8601String())
      ..writeByte(5)
      ..write(obj.isSynced);
  }
}
