import 'package:drift/drift.dart';


@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get nameFa => text().unique()();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Account')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get bankCode => text()();
  TextColumn get accountHint => text().withDefault(const Constant(''))();
  TextColumn get displayName => text().nullable()();
  IntColumn get openingBalanceRial => integer().nullable()();
  IntColumn get lastBalanceRial => integer().nullable()();
  DateTimeColumn get lastBalanceAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {bankCode, accountHint}
      ];
}

@DataClassName('SmsRecord')
class RawSms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get parseStatus => text()();
  TextColumn get templateId => text().nullable()();
  TextColumn get parseErrorCode => text().nullable()();
  TextColumn get bankCode => text().nullable()();
  TextColumn get hash => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {hash}
      ];
}

@DataClassName('TxRecord')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get txUid => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get rawSmsId => integer().nullable().references(RawSms, #id)();
  IntColumn get amountRial => integer().customConstraint('NOT NULL CHECK (amount_rial > 0)')();
  TextColumn get direction => text().customConstraint("NOT NULL CHECK (direction IN ('in','out'))")();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get timeSource => text().withDefault(const Constant('body'))();
  TextColumn get counterparty => text().nullable()();
  TextColumn get counterpartySource => text().nullable()();
  TextColumn get purposeText => text().nullable()();
  TextColumn get label => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending_category'))();
  TextColumn get smsHash => text().nullable()();
  TextColumn get referenceNo => text().nullable()();
  IntColumn get balanceAfterRial => integer().nullable()();
  IntColumn get balanceGapRial => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {txUid},
        {smsHash}
      ];
}

@DataClassName('MemoryEntry')
class MerchantMemory extends Table {
  TextColumn get key => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get useCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('Reminder')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get dueAt => dateTime()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get rolloverCount => integer().withDefault(const Constant(0))();
  IntColumn get followupCount => integer().withDefault(const Constant(2))();
  IntColumn get followupIntervalMin => integer().withDefault(const Constant(15))();
  IntColumn get rev => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Occurrence')
class ReminderOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get reminderId => text().references(Reminders, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get scheduledFor => dateTime()();
  TextColumn get outcome => text().withDefault(const Constant('pending'))();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
  IntColumn get followupsSent => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {reminderId, scheduledFor}
      ];
}

@DataClassName('Setting')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ImportedEvent')
class ImportLog extends Table {
  TextColumn get eventUid => text()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {eventUid};
}
