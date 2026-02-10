import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Drift codegen
part 'app_db.g.dart';

class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get firstName => text().nullable()();
  TextColumn get lastName => text().nullable()();
  TextColumn get company => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ContactChannels extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get contactId => text()();
  TextColumn get source => text()();
  TextColumn get handle => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
}

class ContactLabels extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get contactId => text()();
  TextColumn get labelName => text()();
}

class ContactNotes extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  IntColumn get createdAtMs => integer()();
  // Нельзя называть колонку `text`, потому что в Drift уже есть метод `text()`.
  // Храним в БД колонку с именем `text`, но в Dart-геттере используем другое имя.
  TextColumn get body => text().named('text')();

  @override
  Set<Column> get primaryKey => {id};
}

class ConversationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get contactId => text()();
  TextColumn get source => text()();
  TextColumn get handle => text()();
  TextColumn get lastMessage => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Contacts,
    ContactChannels,
    ContactLabels,
    ContactNotes,
    ConversationsTable,
  ],
)
class AppDb extends _$AppDb {
  AppDb() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'messenger_crm.sqlite'));
    return NativeDatabase(file);
  });
}
