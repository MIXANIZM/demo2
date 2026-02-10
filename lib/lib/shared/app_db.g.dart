// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _companyMeta = const VerificationMeta(
    'company',
  );
  @override
  late final GeneratedColumn<String> company = GeneratedColumn<String>(
    'company',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    firstName,
    lastName,
    company,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Contact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('company')) {
      context.handle(
        _companyMeta,
        company.isAcceptableOrUnknown(data['company']!, _companyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      ),
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      company: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company'],
      ),
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }
}

class Contact extends DataClass implements Insertable<Contact> {
  final String id;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? company;
  const Contact({
    required this.id,
    required this.displayName,
    this.firstName,
    this.lastName,
    this.company,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || firstName != null) {
      map['first_name'] = Variable<String>(firstName);
    }
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || company != null) {
      map['company'] = Variable<String>(company);
    }
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      firstName: firstName == null && nullToAbsent
          ? const Value.absent()
          : Value(firstName),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      company: company == null && nullToAbsent
          ? const Value.absent()
          : Value(company),
    );
  }

  factory Contact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Contact(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      firstName: serializer.fromJson<String?>(json['firstName']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      company: serializer.fromJson<String?>(json['company']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'firstName': serializer.toJson<String?>(firstName),
      'lastName': serializer.toJson<String?>(lastName),
      'company': serializer.toJson<String?>(company),
    };
  }

  Contact copyWith({
    String? id,
    String? displayName,
    Value<String?> firstName = const Value.absent(),
    Value<String?> lastName = const Value.absent(),
    Value<String?> company = const Value.absent(),
  }) => Contact(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    firstName: firstName.present ? firstName.value : this.firstName,
    lastName: lastName.present ? lastName.value : this.lastName,
    company: company.present ? company.value : this.company,
  );
  Contact copyWithCompanion(ContactsCompanion data) {
    return Contact(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      company: data.company.present ? data.company.value : this.company,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Contact(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('company: $company')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, displayName, firstName, lastName, company);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Contact &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.company == this.company);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String?> firstName;
  final Value<String?> lastName;
  final Value<String?> company;
  final Value<int> rowid;
  const ContactsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.company = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactsCompanion.insert({
    required String id,
    required String displayName,
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.company = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName);
  static Insertable<Contact> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? company,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (company != null) 'company': company,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactsCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String?>? firstName,
    Value<String?>? lastName,
    Value<String?>? company,
    Value<int>? rowid,
  }) {
    return ContactsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      company: company ?? this.company,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (company.present) {
      map['company'] = Variable<String>(company.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('company: $company, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactChannelsTable extends ContactChannels
    with TableInfo<$ContactChannelsTable, ContactChannel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<int> rowId = GeneratedColumn<int>(
    'row_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _handleMeta = const VerificationMeta('handle');
  @override
  late final GeneratedColumn<String> handle = GeneratedColumn<String>(
    'handle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowId,
    contactId,
    source,
    handle,
    isPrimary,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactChannel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    }
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('handle')) {
      context.handle(
        _handleMeta,
        handle.isAcceptableOrUnknown(data['handle']!, _handleMeta),
      );
    } else if (isInserting) {
      context.missing(_handleMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  ContactChannel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactChannel(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_id'],
      )!,
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      handle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}handle'],
      )!,
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
    );
  }

  @override
  $ContactChannelsTable createAlias(String alias) {
    return $ContactChannelsTable(attachedDatabase, alias);
  }
}

class ContactChannel extends DataClass implements Insertable<ContactChannel> {
  final int rowId;
  final String contactId;
  final String source;
  final String handle;
  final bool isPrimary;
  const ContactChannel({
    required this.rowId,
    required this.contactId,
    required this.source,
    required this.handle,
    required this.isPrimary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<int>(rowId);
    map['contact_id'] = Variable<String>(contactId);
    map['source'] = Variable<String>(source);
    map['handle'] = Variable<String>(handle);
    map['is_primary'] = Variable<bool>(isPrimary);
    return map;
  }

  ContactChannelsCompanion toCompanion(bool nullToAbsent) {
    return ContactChannelsCompanion(
      rowId: Value(rowId),
      contactId: Value(contactId),
      source: Value(source),
      handle: Value(handle),
      isPrimary: Value(isPrimary),
    );
  }

  factory ContactChannel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactChannel(
      rowId: serializer.fromJson<int>(json['rowId']),
      contactId: serializer.fromJson<String>(json['contactId']),
      source: serializer.fromJson<String>(json['source']),
      handle: serializer.fromJson<String>(json['handle']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowId': serializer.toJson<int>(rowId),
      'contactId': serializer.toJson<String>(contactId),
      'source': serializer.toJson<String>(source),
      'handle': serializer.toJson<String>(handle),
      'isPrimary': serializer.toJson<bool>(isPrimary),
    };
  }

  ContactChannel copyWith({
    int? rowId,
    String? contactId,
    String? source,
    String? handle,
    bool? isPrimary,
  }) => ContactChannel(
    rowId: rowId ?? this.rowId,
    contactId: contactId ?? this.contactId,
    source: source ?? this.source,
    handle: handle ?? this.handle,
    isPrimary: isPrimary ?? this.isPrimary,
  );
  ContactChannel copyWithCompanion(ContactChannelsCompanion data) {
    return ContactChannel(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      source: data.source.present ? data.source.value : this.source,
      handle: data.handle.present ? data.handle.value : this.handle,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactChannel(')
          ..write('rowId: $rowId, ')
          ..write('contactId: $contactId, ')
          ..write('source: $source, ')
          ..write('handle: $handle, ')
          ..write('isPrimary: $isPrimary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rowId, contactId, source, handle, isPrimary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactChannel &&
          other.rowId == this.rowId &&
          other.contactId == this.contactId &&
          other.source == this.source &&
          other.handle == this.handle &&
          other.isPrimary == this.isPrimary);
}

class ContactChannelsCompanion extends UpdateCompanion<ContactChannel> {
  final Value<int> rowId;
  final Value<String> contactId;
  final Value<String> source;
  final Value<String> handle;
  final Value<bool> isPrimary;
  const ContactChannelsCompanion({
    this.rowId = const Value.absent(),
    this.contactId = const Value.absent(),
    this.source = const Value.absent(),
    this.handle = const Value.absent(),
    this.isPrimary = const Value.absent(),
  });
  ContactChannelsCompanion.insert({
    this.rowId = const Value.absent(),
    required String contactId,
    required String source,
    required String handle,
    this.isPrimary = const Value.absent(),
  }) : contactId = Value(contactId),
       source = Value(source),
       handle = Value(handle);
  static Insertable<ContactChannel> custom({
    Expression<int>? rowId,
    Expression<String>? contactId,
    Expression<String>? source,
    Expression<String>? handle,
    Expression<bool>? isPrimary,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (contactId != null) 'contact_id': contactId,
      if (source != null) 'source': source,
      if (handle != null) 'handle': handle,
      if (isPrimary != null) 'is_primary': isPrimary,
    });
  }

  ContactChannelsCompanion copyWith({
    Value<int>? rowId,
    Value<String>? contactId,
    Value<String>? source,
    Value<String>? handle,
    Value<bool>? isPrimary,
  }) {
    return ContactChannelsCompanion(
      rowId: rowId ?? this.rowId,
      contactId: contactId ?? this.contactId,
      source: source ?? this.source,
      handle: handle ?? this.handle,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<int>(rowId.value);
    }
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (handle.present) {
      map['handle'] = Variable<String>(handle.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactChannelsCompanion(')
          ..write('rowId: $rowId, ')
          ..write('contactId: $contactId, ')
          ..write('source: $source, ')
          ..write('handle: $handle, ')
          ..write('isPrimary: $isPrimary')
          ..write(')'))
        .toString();
  }
}

class $ContactLabelsTable extends ContactLabels
    with TableInfo<$ContactLabelsTable, ContactLabel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactLabelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<int> rowId = GeneratedColumn<int>(
    'row_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelNameMeta = const VerificationMeta(
    'labelName',
  );
  @override
  late final GeneratedColumn<String> labelName = GeneratedColumn<String>(
    'label_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [rowId, contactId, labelName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_labels';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactLabel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    }
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('label_name')) {
      context.handle(
        _labelNameMeta,
        labelName.isAcceptableOrUnknown(data['label_name']!, _labelNameMeta),
      );
    } else if (isInserting) {
      context.missing(_labelNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  ContactLabel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactLabel(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_id'],
      )!,
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      labelName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label_name'],
      )!,
    );
  }

  @override
  $ContactLabelsTable createAlias(String alias) {
    return $ContactLabelsTable(attachedDatabase, alias);
  }
}

class ContactLabel extends DataClass implements Insertable<ContactLabel> {
  final int rowId;
  final String contactId;
  final String labelName;
  const ContactLabel({
    required this.rowId,
    required this.contactId,
    required this.labelName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<int>(rowId);
    map['contact_id'] = Variable<String>(contactId);
    map['label_name'] = Variable<String>(labelName);
    return map;
  }

  ContactLabelsCompanion toCompanion(bool nullToAbsent) {
    return ContactLabelsCompanion(
      rowId: Value(rowId),
      contactId: Value(contactId),
      labelName: Value(labelName),
    );
  }

  factory ContactLabel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactLabel(
      rowId: serializer.fromJson<int>(json['rowId']),
      contactId: serializer.fromJson<String>(json['contactId']),
      labelName: serializer.fromJson<String>(json['labelName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowId': serializer.toJson<int>(rowId),
      'contactId': serializer.toJson<String>(contactId),
      'labelName': serializer.toJson<String>(labelName),
    };
  }

  ContactLabel copyWith({int? rowId, String? contactId, String? labelName}) =>
      ContactLabel(
        rowId: rowId ?? this.rowId,
        contactId: contactId ?? this.contactId,
        labelName: labelName ?? this.labelName,
      );
  ContactLabel copyWithCompanion(ContactLabelsCompanion data) {
    return ContactLabel(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      labelName: data.labelName.present ? data.labelName.value : this.labelName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactLabel(')
          ..write('rowId: $rowId, ')
          ..write('contactId: $contactId, ')
          ..write('labelName: $labelName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rowId, contactId, labelName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactLabel &&
          other.rowId == this.rowId &&
          other.contactId == this.contactId &&
          other.labelName == this.labelName);
}

class ContactLabelsCompanion extends UpdateCompanion<ContactLabel> {
  final Value<int> rowId;
  final Value<String> contactId;
  final Value<String> labelName;
  const ContactLabelsCompanion({
    this.rowId = const Value.absent(),
    this.contactId = const Value.absent(),
    this.labelName = const Value.absent(),
  });
  ContactLabelsCompanion.insert({
    this.rowId = const Value.absent(),
    required String contactId,
    required String labelName,
  }) : contactId = Value(contactId),
       labelName = Value(labelName);
  static Insertable<ContactLabel> custom({
    Expression<int>? rowId,
    Expression<String>? contactId,
    Expression<String>? labelName,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (contactId != null) 'contact_id': contactId,
      if (labelName != null) 'label_name': labelName,
    });
  }

  ContactLabelsCompanion copyWith({
    Value<int>? rowId,
    Value<String>? contactId,
    Value<String>? labelName,
  }) {
    return ContactLabelsCompanion(
      rowId: rowId ?? this.rowId,
      contactId: contactId ?? this.contactId,
      labelName: labelName ?? this.labelName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<int>(rowId.value);
    }
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (labelName.present) {
      map['label_name'] = Variable<String>(labelName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactLabelsCompanion(')
          ..write('rowId: $rowId, ')
          ..write('contactId: $contactId, ')
          ..write('labelName: $labelName')
          ..write(')'))
        .toString();
  }
}

class $ContactNotesTable extends ContactNotes
    with TableInfo<$ContactNotesTable, ContactNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, contactId, createdAtMs, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['text']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContactNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
    );
  }

  @override
  $ContactNotesTable createAlias(String alias) {
    return $ContactNotesTable(attachedDatabase, alias);
  }
}

class ContactNote extends DataClass implements Insertable<ContactNote> {
  final String id;
  final String contactId;
  final int createdAtMs;
  final String body;
  const ContactNote({
    required this.id,
    required this.contactId,
    required this.createdAtMs,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['contact_id'] = Variable<String>(contactId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['text'] = Variable<String>(body);
    return map;
  }

  ContactNotesCompanion toCompanion(bool nullToAbsent) {
    return ContactNotesCompanion(
      id: Value(id),
      contactId: Value(contactId),
      createdAtMs: Value(createdAtMs),
      body: Value(body),
    );
  }

  factory ContactNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactNote(
      id: serializer.fromJson<String>(json['id']),
      contactId: serializer.fromJson<String>(json['contactId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'contactId': serializer.toJson<String>(contactId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'body': serializer.toJson<String>(body),
    };
  }

  ContactNote copyWith({
    String? id,
    String? contactId,
    int? createdAtMs,
    String? body,
  }) => ContactNote(
    id: id ?? this.id,
    contactId: contactId ?? this.contactId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    body: body ?? this.body,
  );
  ContactNote copyWithCompanion(ContactNotesCompanion data) {
    return ContactNote(
      id: data.id.present ? data.id.value : this.id,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactNote(')
          ..write('id: $id, ')
          ..write('contactId: $contactId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, contactId, createdAtMs, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactNote &&
          other.id == this.id &&
          other.contactId == this.contactId &&
          other.createdAtMs == this.createdAtMs &&
          other.body == this.body);
}

class ContactNotesCompanion extends UpdateCompanion<ContactNote> {
  final Value<String> id;
  final Value<String> contactId;
  final Value<int> createdAtMs;
  final Value<String> body;
  final Value<int> rowid;
  const ContactNotesCompanion({
    this.id = const Value.absent(),
    this.contactId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactNotesCompanion.insert({
    required String id,
    required String contactId,
    required int createdAtMs,
    required String body,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       contactId = Value(contactId),
       createdAtMs = Value(createdAtMs),
       body = Value(body);
  static Insertable<ContactNote> custom({
    Expression<String>? id,
    Expression<String>? contactId,
    Expression<int>? createdAtMs,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contactId != null) 'contact_id': contactId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (body != null) 'text': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? contactId,
    Value<int>? createdAtMs,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return ContactNotesCompanion(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (body.present) {
      map['text'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactNotesCompanion(')
          ..write('id: $id, ')
          ..write('contactId: $contactId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTableTable extends ConversationsTable
    with TableInfo<$ConversationsTableTable, ConversationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _handleMeta = const VerificationMeta('handle');
  @override
  late final GeneratedColumn<String> handle = GeneratedColumn<String>(
    'handle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageMeta = const VerificationMeta(
    'lastMessage',
  );
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
    'last_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    contactId,
    source,
    handle,
    lastMessage,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('handle')) {
      context.handle(
        _handleMeta,
        handle.isAcceptableOrUnknown(data['handle']!, _handleMeta),
      );
    } else if (isInserting) {
      context.missing(_handleMeta);
    }
    if (data.containsKey('last_message')) {
      context.handle(
        _lastMessageMeta,
        lastMessage.isAcceptableOrUnknown(
          data['last_message']!,
          _lastMessageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      handle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}handle'],
      )!,
      lastMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ConversationsTableTable createAlias(String alias) {
    return $ConversationsTableTable(attachedDatabase, alias);
  }
}

class ConversationsTableData extends DataClass
    implements Insertable<ConversationsTableData> {
  final String id;
  final String contactId;
  final String source;
  final String handle;
  final String lastMessage;
  final int updatedAtMs;
  const ConversationsTableData({
    required this.id,
    required this.contactId,
    required this.source,
    required this.handle,
    required this.lastMessage,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['contact_id'] = Variable<String>(contactId);
    map['source'] = Variable<String>(source);
    map['handle'] = Variable<String>(handle);
    map['last_message'] = Variable<String>(lastMessage);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ConversationsTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationsTableCompanion(
      id: Value(id),
      contactId: Value(contactId),
      source: Value(source),
      handle: Value(handle),
      lastMessage: Value(lastMessage),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ConversationsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationsTableData(
      id: serializer.fromJson<String>(json['id']),
      contactId: serializer.fromJson<String>(json['contactId']),
      source: serializer.fromJson<String>(json['source']),
      handle: serializer.fromJson<String>(json['handle']),
      lastMessage: serializer.fromJson<String>(json['lastMessage']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'contactId': serializer.toJson<String>(contactId),
      'source': serializer.toJson<String>(source),
      'handle': serializer.toJson<String>(handle),
      'lastMessage': serializer.toJson<String>(lastMessage),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ConversationsTableData copyWith({
    String? id,
    String? contactId,
    String? source,
    String? handle,
    String? lastMessage,
    int? updatedAtMs,
  }) => ConversationsTableData(
    id: id ?? this.id,
    contactId: contactId ?? this.contactId,
    source: source ?? this.source,
    handle: handle ?? this.handle,
    lastMessage: lastMessage ?? this.lastMessage,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ConversationsTableData copyWithCompanion(ConversationsTableCompanion data) {
    return ConversationsTableData(
      id: data.id.present ? data.id.value : this.id,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      source: data.source.present ? data.source.value : this.source,
      handle: data.handle.present ? data.handle.value : this.handle,
      lastMessage: data.lastMessage.present
          ? data.lastMessage.value
          : this.lastMessage,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableData(')
          ..write('id: $id, ')
          ..write('contactId: $contactId, ')
          ..write('source: $source, ')
          ..write('handle: $handle, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, contactId, source, handle, lastMessage, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationsTableData &&
          other.id == this.id &&
          other.contactId == this.contactId &&
          other.source == this.source &&
          other.handle == this.handle &&
          other.lastMessage == this.lastMessage &&
          other.updatedAtMs == this.updatedAtMs);
}

class ConversationsTableCompanion
    extends UpdateCompanion<ConversationsTableData> {
  final Value<String> id;
  final Value<String> contactId;
  final Value<String> source;
  final Value<String> handle;
  final Value<String> lastMessage;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ConversationsTableCompanion({
    this.id = const Value.absent(),
    this.contactId = const Value.absent(),
    this.source = const Value.absent(),
    this.handle = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsTableCompanion.insert({
    required String id,
    required String contactId,
    required String source,
    required String handle,
    required String lastMessage,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       contactId = Value(contactId),
       source = Value(source),
       handle = Value(handle),
       lastMessage = Value(lastMessage),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ConversationsTableData> custom({
    Expression<String>? id,
    Expression<String>? contactId,
    Expression<String>? source,
    Expression<String>? handle,
    Expression<String>? lastMessage,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contactId != null) 'contact_id': contactId,
      if (source != null) 'source': source,
      if (handle != null) 'handle': handle,
      if (lastMessage != null) 'last_message': lastMessage,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? contactId,
    Value<String>? source,
    Value<String>? handle,
    Value<String>? lastMessage,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ConversationsTableCompanion(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      source: source ?? this.source,
      handle: handle ?? this.handle,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (handle.present) {
      map['handle'] = Variable<String>(handle.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableCompanion(')
          ..write('id: $id, ')
          ..write('contactId: $contactId, ')
          ..write('source: $source, ')
          ..write('handle: $handle, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $ContactChannelsTable contactChannels = $ContactChannelsTable(
    this,
  );
  late final $ContactLabelsTable contactLabels = $ContactLabelsTable(this);
  late final $ContactNotesTable contactNotes = $ContactNotesTable(this);
  late final $ConversationsTableTable conversationsTable =
      $ConversationsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    contacts,
    contactChannels,
    contactLabels,
    contactNotes,
    conversationsTable,
  ];
}

typedef $$ContactsTableCreateCompanionBuilder =
    ContactsCompanion Function({
      required String id,
      required String displayName,
      Value<String?> firstName,
      Value<String?> lastName,
      Value<String?> company,
      Value<int> rowid,
    });
typedef $$ContactsTableUpdateCompanionBuilder =
    ContactsCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String?> firstName,
      Value<String?> lastName,
      Value<String?> company,
      Value<int> rowid,
    });

class $$ContactsTableFilterComposer extends Composer<_$AppDb, $ContactsTable> {
  $$ContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get company => $composableBuilder(
    column: $table.company,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactsTableOrderingComposer
    extends Composer<_$AppDb, $ContactsTable> {
  $$ContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get company => $composableBuilder(
    column: $table.company,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$AppDb, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get company =>
      $composableBuilder(column: $table.company, builder: (column) => column);
}

class $$ContactsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ContactsTable,
          Contact,
          $$ContactsTableFilterComposer,
          $$ContactsTableOrderingComposer,
          $$ContactsTableAnnotationComposer,
          $$ContactsTableCreateCompanionBuilder,
          $$ContactsTableUpdateCompanionBuilder,
          (Contact, BaseReferences<_$AppDb, $ContactsTable, Contact>),
          Contact,
          PrefetchHooks Function()
        > {
  $$ContactsTableTableManager(_$AppDb db, $ContactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> company = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion(
                id: id,
                displayName: displayName,
                firstName: firstName,
                lastName: lastName,
                company: company,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                Value<String?> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> company = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion.insert(
                id: id,
                displayName: displayName,
                firstName: firstName,
                lastName: lastName,
                company: company,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ContactsTable,
      Contact,
      $$ContactsTableFilterComposer,
      $$ContactsTableOrderingComposer,
      $$ContactsTableAnnotationComposer,
      $$ContactsTableCreateCompanionBuilder,
      $$ContactsTableUpdateCompanionBuilder,
      (Contact, BaseReferences<_$AppDb, $ContactsTable, Contact>),
      Contact,
      PrefetchHooks Function()
    >;
typedef $$ContactChannelsTableCreateCompanionBuilder =
    ContactChannelsCompanion Function({
      Value<int> rowId,
      required String contactId,
      required String source,
      required String handle,
      Value<bool> isPrimary,
    });
typedef $$ContactChannelsTableUpdateCompanionBuilder =
    ContactChannelsCompanion Function({
      Value<int> rowId,
      Value<String> contactId,
      Value<String> source,
      Value<String> handle,
      Value<bool> isPrimary,
    });

class $$ContactChannelsTableFilterComposer
    extends Composer<_$AppDb, $ContactChannelsTable> {
  $$ContactChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get handle => $composableBuilder(
    column: $table.handle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactChannelsTableOrderingComposer
    extends Composer<_$AppDb, $ContactChannelsTable> {
  $$ContactChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get handle => $composableBuilder(
    column: $table.handle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactChannelsTableAnnotationComposer
    extends Composer<_$AppDb, $ContactChannelsTable> {
  $$ContactChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get handle =>
      $composableBuilder(column: $table.handle, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);
}

class $$ContactChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ContactChannelsTable,
          ContactChannel,
          $$ContactChannelsTableFilterComposer,
          $$ContactChannelsTableOrderingComposer,
          $$ContactChannelsTableAnnotationComposer,
          $$ContactChannelsTableCreateCompanionBuilder,
          $$ContactChannelsTableUpdateCompanionBuilder,
          (
            ContactChannel,
            BaseReferences<_$AppDb, $ContactChannelsTable, ContactChannel>,
          ),
          ContactChannel,
          PrefetchHooks Function()
        > {
  $$ContactChannelsTableTableManager(_$AppDb db, $ContactChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> handle = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
              }) => ContactChannelsCompanion(
                rowId: rowId,
                contactId: contactId,
                source: source,
                handle: handle,
                isPrimary: isPrimary,
              ),
          createCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                required String contactId,
                required String source,
                required String handle,
                Value<bool> isPrimary = const Value.absent(),
              }) => ContactChannelsCompanion.insert(
                rowId: rowId,
                contactId: contactId,
                source: source,
                handle: handle,
                isPrimary: isPrimary,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ContactChannelsTable,
      ContactChannel,
      $$ContactChannelsTableFilterComposer,
      $$ContactChannelsTableOrderingComposer,
      $$ContactChannelsTableAnnotationComposer,
      $$ContactChannelsTableCreateCompanionBuilder,
      $$ContactChannelsTableUpdateCompanionBuilder,
      (
        ContactChannel,
        BaseReferences<_$AppDb, $ContactChannelsTable, ContactChannel>,
      ),
      ContactChannel,
      PrefetchHooks Function()
    >;
typedef $$ContactLabelsTableCreateCompanionBuilder =
    ContactLabelsCompanion Function({
      Value<int> rowId,
      required String contactId,
      required String labelName,
    });
typedef $$ContactLabelsTableUpdateCompanionBuilder =
    ContactLabelsCompanion Function({
      Value<int> rowId,
      Value<String> contactId,
      Value<String> labelName,
    });

class $$ContactLabelsTableFilterComposer
    extends Composer<_$AppDb, $ContactLabelsTable> {
  $$ContactLabelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get labelName => $composableBuilder(
    column: $table.labelName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactLabelsTableOrderingComposer
    extends Composer<_$AppDb, $ContactLabelsTable> {
  $$ContactLabelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get labelName => $composableBuilder(
    column: $table.labelName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactLabelsTableAnnotationComposer
    extends Composer<_$AppDb, $ContactLabelsTable> {
  $$ContactLabelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get labelName =>
      $composableBuilder(column: $table.labelName, builder: (column) => column);
}

class $$ContactLabelsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ContactLabelsTable,
          ContactLabel,
          $$ContactLabelsTableFilterComposer,
          $$ContactLabelsTableOrderingComposer,
          $$ContactLabelsTableAnnotationComposer,
          $$ContactLabelsTableCreateCompanionBuilder,
          $$ContactLabelsTableUpdateCompanionBuilder,
          (
            ContactLabel,
            BaseReferences<_$AppDb, $ContactLabelsTable, ContactLabel>,
          ),
          ContactLabel,
          PrefetchHooks Function()
        > {
  $$ContactLabelsTableTableManager(_$AppDb db, $ContactLabelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactLabelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactLabelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactLabelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<String> labelName = const Value.absent(),
              }) => ContactLabelsCompanion(
                rowId: rowId,
                contactId: contactId,
                labelName: labelName,
              ),
          createCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                required String contactId,
                required String labelName,
              }) => ContactLabelsCompanion.insert(
                rowId: rowId,
                contactId: contactId,
                labelName: labelName,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactLabelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ContactLabelsTable,
      ContactLabel,
      $$ContactLabelsTableFilterComposer,
      $$ContactLabelsTableOrderingComposer,
      $$ContactLabelsTableAnnotationComposer,
      $$ContactLabelsTableCreateCompanionBuilder,
      $$ContactLabelsTableUpdateCompanionBuilder,
      (
        ContactLabel,
        BaseReferences<_$AppDb, $ContactLabelsTable, ContactLabel>,
      ),
      ContactLabel,
      PrefetchHooks Function()
    >;
typedef $$ContactNotesTableCreateCompanionBuilder =
    ContactNotesCompanion Function({
      required String id,
      required String contactId,
      required int createdAtMs,
      required String body,
      Value<int> rowid,
    });
typedef $$ContactNotesTableUpdateCompanionBuilder =
    ContactNotesCompanion Function({
      Value<String> id,
      Value<String> contactId,
      Value<int> createdAtMs,
      Value<String> body,
      Value<int> rowid,
    });

class $$ContactNotesTableFilterComposer
    extends Composer<_$AppDb, $ContactNotesTable> {
  $$ContactNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactNotesTableOrderingComposer
    extends Composer<_$AppDb, $ContactNotesTable> {
  $$ContactNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactNotesTableAnnotationComposer
    extends Composer<_$AppDb, $ContactNotesTable> {
  $$ContactNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$ContactNotesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ContactNotesTable,
          ContactNote,
          $$ContactNotesTableFilterComposer,
          $$ContactNotesTableOrderingComposer,
          $$ContactNotesTableAnnotationComposer,
          $$ContactNotesTableCreateCompanionBuilder,
          $$ContactNotesTableUpdateCompanionBuilder,
          (
            ContactNote,
            BaseReferences<_$AppDb, $ContactNotesTable, ContactNote>,
          ),
          ContactNote,
          PrefetchHooks Function()
        > {
  $$ContactNotesTableTableManager(_$AppDb db, $ContactNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactNotesCompanion(
                id: id,
                contactId: contactId,
                createdAtMs: createdAtMs,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String contactId,
                required int createdAtMs,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => ContactNotesCompanion.insert(
                id: id,
                contactId: contactId,
                createdAtMs: createdAtMs,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ContactNotesTable,
      ContactNote,
      $$ContactNotesTableFilterComposer,
      $$ContactNotesTableOrderingComposer,
      $$ContactNotesTableAnnotationComposer,
      $$ContactNotesTableCreateCompanionBuilder,
      $$ContactNotesTableUpdateCompanionBuilder,
      (ContactNote, BaseReferences<_$AppDb, $ContactNotesTable, ContactNote>),
      ContactNote,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableTableCreateCompanionBuilder =
    ConversationsTableCompanion Function({
      required String id,
      required String contactId,
      required String source,
      required String handle,
      required String lastMessage,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ConversationsTableTableUpdateCompanionBuilder =
    ConversationsTableCompanion Function({
      Value<String> id,
      Value<String> contactId,
      Value<String> source,
      Value<String> handle,
      Value<String> lastMessage,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ConversationsTableTableFilterComposer
    extends Composer<_$AppDb, $ConversationsTableTable> {
  $$ConversationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get handle => $composableBuilder(
    column: $table.handle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableTableOrderingComposer
    extends Composer<_$AppDb, $ConversationsTableTable> {
  $$ConversationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get handle => $composableBuilder(
    column: $table.handle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableTableAnnotationComposer
    extends Composer<_$AppDb, $ConversationsTableTable> {
  $$ConversationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get handle =>
      $composableBuilder(column: $table.handle, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ConversationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ConversationsTableTable,
          ConversationsTableData,
          $$ConversationsTableTableFilterComposer,
          $$ConversationsTableTableOrderingComposer,
          $$ConversationsTableTableAnnotationComposer,
          $$ConversationsTableTableCreateCompanionBuilder,
          $$ConversationsTableTableUpdateCompanionBuilder,
          (
            ConversationsTableData,
            BaseReferences<
              _$AppDb,
              $ConversationsTableTable,
              ConversationsTableData
            >,
          ),
          ConversationsTableData,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableTableManager(
    _$AppDb db,
    $ConversationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> handle = const Value.absent(),
                Value<String> lastMessage = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsTableCompanion(
                id: id,
                contactId: contactId,
                source: source,
                handle: handle,
                lastMessage: lastMessage,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String contactId,
                required String source,
                required String handle,
                required String lastMessage,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsTableCompanion.insert(
                id: id,
                contactId: contactId,
                source: source,
                handle: handle,
                lastMessage: lastMessage,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ConversationsTableTable,
      ConversationsTableData,
      $$ConversationsTableTableFilterComposer,
      $$ConversationsTableTableOrderingComposer,
      $$ConversationsTableTableAnnotationComposer,
      $$ConversationsTableTableCreateCompanionBuilder,
      $$ConversationsTableTableUpdateCompanionBuilder,
      (
        ConversationsTableData,
        BaseReferences<
          _$AppDb,
          $ConversationsTableTable,
          ConversationsTableData
        >,
      ),
      ConversationsTableData,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$ContactChannelsTableTableManager get contactChannels =>
      $$ContactChannelsTableTableManager(_db, _db.contactChannels);
  $$ContactLabelsTableTableManager get contactLabels =>
      $$ContactLabelsTableTableManager(_db, _db.contactLabels);
  $$ContactNotesTableTableManager get contactNotes =>
      $$ContactNotesTableTableManager(_db, _db.contactNotes);
  $$ConversationsTableTableTableManager get conversationsTable =>
      $$ConversationsTableTableTableManager(_db, _db.conversationsTable);
}
