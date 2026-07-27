// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CacheMetaTable extends CacheMeta
    with TableInfo<$CacheMetaTable, CacheMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId};
  @override
  CacheMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheMetaData(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CacheMetaTable createAlias(String alias) {
    return $CacheMetaTable(attachedDatabase, alias);
  }
}

class CacheMetaData extends DataClass implements Insertable<CacheMetaData> {
  final String tenantId;
  final DateTime fetchedAt;
  const CacheMetaData({required this.tenantId, required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CacheMetaCompanion toCompanion(bool nullToAbsent) {
    return CacheMetaCompanion(
      tenantId: Value(tenantId),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CacheMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheMetaData(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CacheMetaData copyWith({String? tenantId, DateTime? fetchedAt}) =>
      CacheMetaData(
        tenantId: tenantId ?? this.tenantId,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  CacheMetaData copyWithCompanion(CacheMetaCompanion data) {
    return CacheMetaData(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaData(')
          ..write('tenantId: $tenantId, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheMetaData &&
          other.tenantId == this.tenantId &&
          other.fetchedAt == this.fetchedAt);
}

class CacheMetaCompanion extends UpdateCompanion<CacheMetaData> {
  final Value<String> tenantId;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CacheMetaCompanion({
    this.tenantId = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheMetaCompanion.insert({
    required String tenantId,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       fetchedAt = Value(fetchedAt);
  static Insertable<CacheMetaData> custom({
    Expression<String>? tenantId,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheMetaCompanion copyWith({
    Value<String>? tenantId,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CacheMetaCompanion(
      tenantId: tenantId ?? this.tenantId,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCategoriesTable extends CachedCategories
    with TableInfo<$CachedCategoriesTable, CachedCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, id, name, sort];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCategory(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $CachedCategoriesTable createAlias(String alias) {
    return $CachedCategoriesTable(attachedDatabase, alias);
  }
}

class CachedCategory extends DataClass implements Insertable<CachedCategory> {
  final String tenantId;
  final String id;
  final String name;
  final int sort;
  const CachedCategory({
    required this.tenantId,
    required this.id,
    required this.name,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  CachedCategoriesCompanion toCompanion(bool nullToAbsent) {
    return CachedCategoriesCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      name: Value(name),
      sort: Value(sort),
    );
  }

  factory CachedCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCategory(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sort': serializer.toJson<int>(sort),
    };
  }

  CachedCategory copyWith({
    String? tenantId,
    String? id,
    String? name,
    int? sort,
  }) => CachedCategory(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    name: name ?? this.name,
    sort: sort ?? this.sort,
  );
  CachedCategory copyWithCompanion(CachedCategoriesCompanion data) {
    return CachedCategory(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCategory(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, id, name, sort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCategory &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.name == this.name &&
          other.sort == this.sort);
}

class CachedCategoriesCompanion extends UpdateCompanion<CachedCategory> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> sort;
  final Value<int> rowid;
  const CachedCategoriesCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCategoriesCompanion.insert({
    required String tenantId,
    required String id,
    required String name,
    required int sort,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<CachedCategory> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCategoriesCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return CachedCategoriesCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      name: name ?? this.name,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCategoriesCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMenuItemsTable extends CachedMenuItems
    with TableInfo<$CachedMenuItemsTable, CachedMenuItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMenuItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _basePriceCentsMeta = const VerificationMeta(
    'basePriceCents',
  );
  @override
  late final GeneratedColumn<int> basePriceCents = GeneratedColumn<int>(
    'base_price_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _is86Meta = const VerificationMeta('is86');
  @override
  late final GeneratedColumn<bool> is86 = GeneratedColumn<bool>(
    'is86',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is86" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isVegMeta = const VerificationMeta('isVeg');
  @override
  late final GeneratedColumn<bool> isVeg = GeneratedColumn<bool>(
    'is_veg',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_veg" IN (0, 1))',
    ),
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tenantId,
    id,
    name,
    basePriceCents,
    categoryId,
    is86,
    isVeg,
    imageUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_menu_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMenuItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_price_cents')) {
      context.handle(
        _basePriceCentsMeta,
        basePriceCents.isAcceptableOrUnknown(
          data['base_price_cents']!,
          _basePriceCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_basePriceCentsMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('is86')) {
      context.handle(
        _is86Meta,
        is86.isAcceptableOrUnknown(data['is86']!, _is86Meta),
      );
    } else if (isInserting) {
      context.missing(_is86Meta);
    }
    if (data.containsKey('is_veg')) {
      context.handle(
        _isVegMeta,
        isVeg.isAcceptableOrUnknown(data['is_veg']!, _isVegMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedMenuItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMenuItem(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      basePriceCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_price_cents'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      is86: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is86'],
      )!,
      isVeg: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_veg'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
    );
  }

  @override
  $CachedMenuItemsTable createAlias(String alias) {
    return $CachedMenuItemsTable(attachedDatabase, alias);
  }
}

class CachedMenuItem extends DataClass implements Insertable<CachedMenuItem> {
  final String tenantId;
  final String id;
  final String name;
  final int basePriceCents;
  final String? categoryId;
  final bool is86;

  /// Nullable on purpose — "unmarked" is a real state that must render nothing.
  final bool? isVeg;
  final String? imageUrl;
  const CachedMenuItem({
    required this.tenantId,
    required this.id,
    required this.name,
    required this.basePriceCents,
    this.categoryId,
    required this.is86,
    this.isVeg,
    this.imageUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['base_price_cents'] = Variable<int>(basePriceCents);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['is86'] = Variable<bool>(is86);
    if (!nullToAbsent || isVeg != null) {
      map['is_veg'] = Variable<bool>(isVeg);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    return map;
  }

  CachedMenuItemsCompanion toCompanion(bool nullToAbsent) {
    return CachedMenuItemsCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      name: Value(name),
      basePriceCents: Value(basePriceCents),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      is86: Value(is86),
      isVeg: isVeg == null && nullToAbsent
          ? const Value.absent()
          : Value(isVeg),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
    );
  }

  factory CachedMenuItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMenuItem(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      basePriceCents: serializer.fromJson<int>(json['basePriceCents']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      is86: serializer.fromJson<bool>(json['is86']),
      isVeg: serializer.fromJson<bool?>(json['isVeg']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'basePriceCents': serializer.toJson<int>(basePriceCents),
      'categoryId': serializer.toJson<String?>(categoryId),
      'is86': serializer.toJson<bool>(is86),
      'isVeg': serializer.toJson<bool?>(isVeg),
      'imageUrl': serializer.toJson<String?>(imageUrl),
    };
  }

  CachedMenuItem copyWith({
    String? tenantId,
    String? id,
    String? name,
    int? basePriceCents,
    Value<String?> categoryId = const Value.absent(),
    bool? is86,
    Value<bool?> isVeg = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
  }) => CachedMenuItem(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    name: name ?? this.name,
    basePriceCents: basePriceCents ?? this.basePriceCents,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    is86: is86 ?? this.is86,
    isVeg: isVeg.present ? isVeg.value : this.isVeg,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
  );
  CachedMenuItem copyWithCompanion(CachedMenuItemsCompanion data) {
    return CachedMenuItem(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      basePriceCents: data.basePriceCents.present
          ? data.basePriceCents.value
          : this.basePriceCents,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      is86: data.is86.present ? data.is86.value : this.is86,
      isVeg: data.isVeg.present ? data.isVeg.value : this.isVeg,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMenuItem(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('basePriceCents: $basePriceCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('is86: $is86, ')
          ..write('isVeg: $isVeg, ')
          ..write('imageUrl: $imageUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tenantId,
    id,
    name,
    basePriceCents,
    categoryId,
    is86,
    isVeg,
    imageUrl,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMenuItem &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.name == this.name &&
          other.basePriceCents == this.basePriceCents &&
          other.categoryId == this.categoryId &&
          other.is86 == this.is86 &&
          other.isVeg == this.isVeg &&
          other.imageUrl == this.imageUrl);
}

class CachedMenuItemsCompanion extends UpdateCompanion<CachedMenuItem> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> basePriceCents;
  final Value<String?> categoryId;
  final Value<bool> is86;
  final Value<bool?> isVeg;
  final Value<String?> imageUrl;
  final Value<int> rowid;
  const CachedMenuItemsCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.basePriceCents = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.is86 = const Value.absent(),
    this.isVeg = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMenuItemsCompanion.insert({
    required String tenantId,
    required String id,
    required String name,
    required int basePriceCents,
    this.categoryId = const Value.absent(),
    required bool is86,
    this.isVeg = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       name = Value(name),
       basePriceCents = Value(basePriceCents),
       is86 = Value(is86);
  static Insertable<CachedMenuItem> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? basePriceCents,
    Expression<String>? categoryId,
    Expression<bool>? is86,
    Expression<bool>? isVeg,
    Expression<String>? imageUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (basePriceCents != null) 'base_price_cents': basePriceCents,
      if (categoryId != null) 'category_id': categoryId,
      if (is86 != null) 'is86': is86,
      if (isVeg != null) 'is_veg': isVeg,
      if (imageUrl != null) 'image_url': imageUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMenuItemsCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? basePriceCents,
    Value<String?>? categoryId,
    Value<bool>? is86,
    Value<bool?>? isVeg,
    Value<String?>? imageUrl,
    Value<int>? rowid,
  }) {
    return CachedMenuItemsCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      name: name ?? this.name,
      basePriceCents: basePriceCents ?? this.basePriceCents,
      categoryId: categoryId ?? this.categoryId,
      is86: is86 ?? this.is86,
      isVeg: isVeg ?? this.isVeg,
      imageUrl: imageUrl ?? this.imageUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (basePriceCents.present) {
      map['base_price_cents'] = Variable<int>(basePriceCents.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (is86.present) {
      map['is86'] = Variable<bool>(is86.value);
    }
    if (isVeg.present) {
      map['is_veg'] = Variable<bool>(isVeg.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMenuItemsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('basePriceCents: $basePriceCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('is86: $is86, ')
          ..write('isVeg: $isVeg, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedVariantsTable extends CachedVariants
    with TableInfo<$CachedVariantsTable, CachedVariant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedVariantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceDeltaCentsMeta = const VerificationMeta(
    'priceDeltaCents',
  );
  @override
  late final GeneratedColumn<int> priceDeltaCents = GeneratedColumn<int>(
    'price_delta_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tenantId,
    id,
    itemId,
    name,
    priceDeltaCents,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedVariant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_delta_cents')) {
      context.handle(
        _priceDeltaCentsMeta,
        priceDeltaCents.isAcceptableOrUnknown(
          data['price_delta_cents']!,
          _priceDeltaCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priceDeltaCentsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedVariant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedVariant(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceDeltaCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_delta_cents'],
      )!,
    );
  }

  @override
  $CachedVariantsTable createAlias(String alias) {
    return $CachedVariantsTable(attachedDatabase, alias);
  }
}

class CachedVariant extends DataClass implements Insertable<CachedVariant> {
  final String tenantId;
  final String id;
  final String itemId;
  final String name;
  final int priceDeltaCents;
  const CachedVariant({
    required this.tenantId,
    required this.id,
    required this.itemId,
    required this.name,
    required this.priceDeltaCents,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['name'] = Variable<String>(name);
    map['price_delta_cents'] = Variable<int>(priceDeltaCents);
    return map;
  }

  CachedVariantsCompanion toCompanion(bool nullToAbsent) {
    return CachedVariantsCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      itemId: Value(itemId),
      name: Value(name),
      priceDeltaCents: Value(priceDeltaCents),
    );
  }

  factory CachedVariant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedVariant(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      name: serializer.fromJson<String>(json['name']),
      priceDeltaCents: serializer.fromJson<int>(json['priceDeltaCents']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'name': serializer.toJson<String>(name),
      'priceDeltaCents': serializer.toJson<int>(priceDeltaCents),
    };
  }

  CachedVariant copyWith({
    String? tenantId,
    String? id,
    String? itemId,
    String? name,
    int? priceDeltaCents,
  }) => CachedVariant(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    name: name ?? this.name,
    priceDeltaCents: priceDeltaCents ?? this.priceDeltaCents,
  );
  CachedVariant copyWithCompanion(CachedVariantsCompanion data) {
    return CachedVariant(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      name: data.name.present ? data.name.value : this.name,
      priceDeltaCents: data.priceDeltaCents.present
          ? data.priceDeltaCents.value
          : this.priceDeltaCents,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedVariant(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaCents: $priceDeltaCents')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, id, itemId, name, priceDeltaCents);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedVariant &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.name == this.name &&
          other.priceDeltaCents == this.priceDeltaCents);
}

class CachedVariantsCompanion extends UpdateCompanion<CachedVariant> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> name;
  final Value<int> priceDeltaCents;
  final Value<int> rowid;
  const CachedVariantsCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.name = const Value.absent(),
    this.priceDeltaCents = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedVariantsCompanion.insert({
    required String tenantId,
    required String id,
    required String itemId,
    required String name,
    required int priceDeltaCents,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       itemId = Value(itemId),
       name = Value(name),
       priceDeltaCents = Value(priceDeltaCents);
  static Insertable<CachedVariant> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? name,
    Expression<int>? priceDeltaCents,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (name != null) 'name': name,
      if (priceDeltaCents != null) 'price_delta_cents': priceDeltaCents,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedVariantsCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? itemId,
    Value<String>? name,
    Value<int>? priceDeltaCents,
    Value<int>? rowid,
  }) {
    return CachedVariantsCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      priceDeltaCents: priceDeltaCents ?? this.priceDeltaCents,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceDeltaCents.present) {
      map['price_delta_cents'] = Variable<int>(priceDeltaCents.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedVariantsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaCents: $priceDeltaCents, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedModifiersTable extends CachedModifiers
    with TableInfo<$CachedModifiersTable, CachedModifier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedModifiersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceCentsMeta = const VerificationMeta(
    'priceCents',
  );
  @override
  late final GeneratedColumn<int> priceCents = GeneratedColumn<int>(
    'price_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, id, name, priceCents];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_modifiers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedModifier> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_cents')) {
      context.handle(
        _priceCentsMeta,
        priceCents.isAcceptableOrUnknown(data['price_cents']!, _priceCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_priceCentsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedModifier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedModifier(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_cents'],
      )!,
    );
  }

  @override
  $CachedModifiersTable createAlias(String alias) {
    return $CachedModifiersTable(attachedDatabase, alias);
  }
}

class CachedModifier extends DataClass implements Insertable<CachedModifier> {
  final String tenantId;
  final String id;
  final String name;
  final int priceCents;
  const CachedModifier({
    required this.tenantId,
    required this.id,
    required this.name,
    required this.priceCents,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['price_cents'] = Variable<int>(priceCents);
    return map;
  }

  CachedModifiersCompanion toCompanion(bool nullToAbsent) {
    return CachedModifiersCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      name: Value(name),
      priceCents: Value(priceCents),
    );
  }

  factory CachedModifier.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedModifier(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      priceCents: serializer.fromJson<int>(json['priceCents']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'priceCents': serializer.toJson<int>(priceCents),
    };
  }

  CachedModifier copyWith({
    String? tenantId,
    String? id,
    String? name,
    int? priceCents,
  }) => CachedModifier(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    name: name ?? this.name,
    priceCents: priceCents ?? this.priceCents,
  );
  CachedModifier copyWithCompanion(CachedModifiersCompanion data) {
    return CachedModifier(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      priceCents: data.priceCents.present
          ? data.priceCents.value
          : this.priceCents,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedModifier(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('priceCents: $priceCents')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, id, name, priceCents);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedModifier &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.name == this.name &&
          other.priceCents == this.priceCents);
}

class CachedModifiersCompanion extends UpdateCompanion<CachedModifier> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> priceCents;
  final Value<int> rowid;
  const CachedModifiersCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.priceCents = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedModifiersCompanion.insert({
    required String tenantId,
    required String id,
    required String name,
    required int priceCents,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       name = Value(name),
       priceCents = Value(priceCents);
  static Insertable<CachedModifier> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? priceCents,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (priceCents != null) 'price_cents': priceCents,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedModifiersCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? priceCents,
    Value<int>? rowid,
  }) {
    return CachedModifiersCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      name: name ?? this.name,
      priceCents: priceCents ?? this.priceCents,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceCents.present) {
      map['price_cents'] = Variable<int>(priceCents.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedModifiersCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('priceCents: $priceCents, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedItemModifiersTable extends CachedItemModifiers
    with TableInfo<$CachedItemModifiersTable, CachedItemModifier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedItemModifiersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifierIdMeta = const VerificationMeta(
    'modifierId',
  );
  @override
  late final GeneratedColumn<String> modifierId = GeneratedColumn<String>(
    'modifier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, itemId, modifierId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_item_modifiers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedItemModifier> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('modifier_id')) {
      context.handle(
        _modifierIdMeta,
        modifierId.isAcceptableOrUnknown(data['modifier_id']!, _modifierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modifierIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, itemId, modifierId};
  @override
  CachedItemModifier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedItemModifier(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      modifierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}modifier_id'],
      )!,
    );
  }

  @override
  $CachedItemModifiersTable createAlias(String alias) {
    return $CachedItemModifiersTable(attachedDatabase, alias);
  }
}

class CachedItemModifier extends DataClass
    implements Insertable<CachedItemModifier> {
  final String tenantId;
  final String itemId;
  final String modifierId;
  const CachedItemModifier({
    required this.tenantId,
    required this.itemId,
    required this.modifierId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['item_id'] = Variable<String>(itemId);
    map['modifier_id'] = Variable<String>(modifierId);
    return map;
  }

  CachedItemModifiersCompanion toCompanion(bool nullToAbsent) {
    return CachedItemModifiersCompanion(
      tenantId: Value(tenantId),
      itemId: Value(itemId),
      modifierId: Value(modifierId),
    );
  }

  factory CachedItemModifier.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedItemModifier(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      modifierId: serializer.fromJson<String>(json['modifierId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'itemId': serializer.toJson<String>(itemId),
      'modifierId': serializer.toJson<String>(modifierId),
    };
  }

  CachedItemModifier copyWith({
    String? tenantId,
    String? itemId,
    String? modifierId,
  }) => CachedItemModifier(
    tenantId: tenantId ?? this.tenantId,
    itemId: itemId ?? this.itemId,
    modifierId: modifierId ?? this.modifierId,
  );
  CachedItemModifier copyWithCompanion(CachedItemModifiersCompanion data) {
    return CachedItemModifier(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      modifierId: data.modifierId.present
          ? data.modifierId.value
          : this.modifierId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedItemModifier(')
          ..write('tenantId: $tenantId, ')
          ..write('itemId: $itemId, ')
          ..write('modifierId: $modifierId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, itemId, modifierId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedItemModifier &&
          other.tenantId == this.tenantId &&
          other.itemId == this.itemId &&
          other.modifierId == this.modifierId);
}

class CachedItemModifiersCompanion extends UpdateCompanion<CachedItemModifier> {
  final Value<String> tenantId;
  final Value<String> itemId;
  final Value<String> modifierId;
  final Value<int> rowid;
  const CachedItemModifiersCompanion({
    this.tenantId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.modifierId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedItemModifiersCompanion.insert({
    required String tenantId,
    required String itemId,
    required String modifierId,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       itemId = Value(itemId),
       modifierId = Value(modifierId);
  static Insertable<CachedItemModifier> custom({
    Expression<String>? tenantId,
    Expression<String>? itemId,
    Expression<String>? modifierId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (itemId != null) 'item_id': itemId,
      if (modifierId != null) 'modifier_id': modifierId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedItemModifiersCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? itemId,
    Value<String>? modifierId,
    Value<int>? rowid,
  }) {
    return CachedItemModifiersCompanion(
      tenantId: tenantId ?? this.tenantId,
      itemId: itemId ?? this.itemId,
      modifierId: modifierId ?? this.modifierId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (modifierId.present) {
      map['modifier_id'] = Variable<String>(modifierId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedItemModifiersCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('itemId: $itemId, ')
          ..write('modifierId: $modifierId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFloorsTable extends CachedFloors
    with TableInfo<$CachedFloorsTable, CachedFloor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFloorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, id, name, sort];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_floors';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFloor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedFloor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFloor(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $CachedFloorsTable createAlias(String alias) {
    return $CachedFloorsTable(attachedDatabase, alias);
  }
}

class CachedFloor extends DataClass implements Insertable<CachedFloor> {
  final String tenantId;
  final String id;
  final String name;
  final int sort;
  const CachedFloor({
    required this.tenantId,
    required this.id,
    required this.name,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  CachedFloorsCompanion toCompanion(bool nullToAbsent) {
    return CachedFloorsCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      name: Value(name),
      sort: Value(sort),
    );
  }

  factory CachedFloor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFloor(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sort': serializer.toJson<int>(sort),
    };
  }

  CachedFloor copyWith({
    String? tenantId,
    String? id,
    String? name,
    int? sort,
  }) => CachedFloor(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    name: name ?? this.name,
    sort: sort ?? this.sort,
  );
  CachedFloor copyWithCompanion(CachedFloorsCompanion data) {
    return CachedFloor(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFloor(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, id, name, sort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFloor &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.name == this.name &&
          other.sort == this.sort);
}

class CachedFloorsCompanion extends UpdateCompanion<CachedFloor> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> sort;
  final Value<int> rowid;
  const CachedFloorsCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFloorsCompanion.insert({
    required String tenantId,
    required String id,
    required String name,
    required int sort,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<CachedFloor> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFloorsCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return CachedFloorsCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      name: name ?? this.name,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFloorsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTablesTable extends CachedTables
    with TableInfo<$CachedTablesTable, CachedTable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capacityMeta = const VerificationMeta(
    'capacity',
  );
  @override
  late final GeneratedColumn<int> capacity = GeneratedColumn<int>(
    'capacity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _floorIdMeta = const VerificationMeta(
    'floorId',
  );
  @override
  late final GeneratedColumn<String> floorId = GeneratedColumn<String>(
    'floor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentOrderIdMeta = const VerificationMeta(
    'currentOrderId',
  );
  @override
  late final GeneratedColumn<String> currentOrderId = GeneratedColumn<String>(
    'current_order_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tenantId,
    id,
    label,
    capacity,
    state,
    floorId,
    currentOrderId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_tables';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedTable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('capacity')) {
      context.handle(
        _capacityMeta,
        capacity.isAcceptableOrUnknown(data['capacity']!, _capacityMeta),
      );
    } else if (isInserting) {
      context.missing(_capacityMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('floor_id')) {
      context.handle(
        _floorIdMeta,
        floorId.isAcceptableOrUnknown(data['floor_id']!, _floorIdMeta),
      );
    }
    if (data.containsKey('current_order_id')) {
      context.handle(
        _currentOrderIdMeta,
        currentOrderId.isAcceptableOrUnknown(
          data['current_order_id']!,
          _currentOrderIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, id};
  @override
  CachedTable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTable(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      capacity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capacity'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      floorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}floor_id'],
      ),
      currentOrderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_order_id'],
      ),
    );
  }

  @override
  $CachedTablesTable createAlias(String alias) {
    return $CachedTablesTable(attachedDatabase, alias);
  }
}

class CachedTable extends DataClass implements Insertable<CachedTable> {
  final String tenantId;
  final String id;
  final String label;
  final int capacity;
  final String state;
  final String? floorId;
  final String? currentOrderId;
  const CachedTable({
    required this.tenantId,
    required this.id,
    required this.label,
    required this.capacity,
    required this.state,
    this.floorId,
    this.currentOrderId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['capacity'] = Variable<int>(capacity);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || floorId != null) {
      map['floor_id'] = Variable<String>(floorId);
    }
    if (!nullToAbsent || currentOrderId != null) {
      map['current_order_id'] = Variable<String>(currentOrderId);
    }
    return map;
  }

  CachedTablesCompanion toCompanion(bool nullToAbsent) {
    return CachedTablesCompanion(
      tenantId: Value(tenantId),
      id: Value(id),
      label: Value(label),
      capacity: Value(capacity),
      state: Value(state),
      floorId: floorId == null && nullToAbsent
          ? const Value.absent()
          : Value(floorId),
      currentOrderId: currentOrderId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentOrderId),
    );
  }

  factory CachedTable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTable(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      capacity: serializer.fromJson<int>(json['capacity']),
      state: serializer.fromJson<String>(json['state']),
      floorId: serializer.fromJson<String?>(json['floorId']),
      currentOrderId: serializer.fromJson<String?>(json['currentOrderId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'capacity': serializer.toJson<int>(capacity),
      'state': serializer.toJson<String>(state),
      'floorId': serializer.toJson<String?>(floorId),
      'currentOrderId': serializer.toJson<String?>(currentOrderId),
    };
  }

  CachedTable copyWith({
    String? tenantId,
    String? id,
    String? label,
    int? capacity,
    String? state,
    Value<String?> floorId = const Value.absent(),
    Value<String?> currentOrderId = const Value.absent(),
  }) => CachedTable(
    tenantId: tenantId ?? this.tenantId,
    id: id ?? this.id,
    label: label ?? this.label,
    capacity: capacity ?? this.capacity,
    state: state ?? this.state,
    floorId: floorId.present ? floorId.value : this.floorId,
    currentOrderId: currentOrderId.present
        ? currentOrderId.value
        : this.currentOrderId,
  );
  CachedTable copyWithCompanion(CachedTablesCompanion data) {
    return CachedTable(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      capacity: data.capacity.present ? data.capacity.value : this.capacity,
      state: data.state.present ? data.state.value : this.state,
      floorId: data.floorId.present ? data.floorId.value : this.floorId,
      currentOrderId: data.currentOrderId.present
          ? data.currentOrderId.value
          : this.currentOrderId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTable(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('capacity: $capacity, ')
          ..write('state: $state, ')
          ..write('floorId: $floorId, ')
          ..write('currentOrderId: $currentOrderId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tenantId,
    id,
    label,
    capacity,
    state,
    floorId,
    currentOrderId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTable &&
          other.tenantId == this.tenantId &&
          other.id == this.id &&
          other.label == this.label &&
          other.capacity == this.capacity &&
          other.state == this.state &&
          other.floorId == this.floorId &&
          other.currentOrderId == this.currentOrderId);
}

class CachedTablesCompanion extends UpdateCompanion<CachedTable> {
  final Value<String> tenantId;
  final Value<String> id;
  final Value<String> label;
  final Value<int> capacity;
  final Value<String> state;
  final Value<String?> floorId;
  final Value<String?> currentOrderId;
  final Value<int> rowid;
  const CachedTablesCompanion({
    this.tenantId = const Value.absent(),
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.capacity = const Value.absent(),
    this.state = const Value.absent(),
    this.floorId = const Value.absent(),
    this.currentOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTablesCompanion.insert({
    required String tenantId,
    required String id,
    required String label,
    required int capacity,
    required String state,
    this.floorId = const Value.absent(),
    this.currentOrderId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       id = Value(id),
       label = Value(label),
       capacity = Value(capacity),
       state = Value(state);
  static Insertable<CachedTable> custom({
    Expression<String>? tenantId,
    Expression<String>? id,
    Expression<String>? label,
    Expression<int>? capacity,
    Expression<String>? state,
    Expression<String>? floorId,
    Expression<String>? currentOrderId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (capacity != null) 'capacity': capacity,
      if (state != null) 'state': state,
      if (floorId != null) 'floor_id': floorId,
      if (currentOrderId != null) 'current_order_id': currentOrderId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTablesCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? id,
    Value<String>? label,
    Value<int>? capacity,
    Value<String>? state,
    Value<String?>? floorId,
    Value<String?>? currentOrderId,
    Value<int>? rowid,
  }) {
    return CachedTablesCompanion(
      tenantId: tenantId ?? this.tenantId,
      id: id ?? this.id,
      label: label ?? this.label,
      capacity: capacity ?? this.capacity,
      state: state ?? this.state,
      floorId: floorId ?? this.floorId,
      currentOrderId: currentOrderId ?? this.currentOrderId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (capacity.present) {
      map['capacity'] = Variable<int>(capacity.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (floorId.present) {
      map['floor_id'] = Variable<String>(floorId.value);
    }
    if (currentOrderId.present) {
      map['current_order_id'] = Variable<String>(currentOrderId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTablesCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('capacity: $capacity, ')
          ..write('state: $state, ')
          ..write('floorId: $floorId, ')
          ..write('currentOrderId: $currentOrderId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMembershipsTable extends CachedMemberships
    with TableInfo<$CachedMembershipsTable, CachedMembership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMembershipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tenantId,
    name,
    slug,
    role,
    currency,
    timezone,
    sortIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_memberships';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMembership> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timezoneMeta);
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_sortIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId};
  @override
  CachedMembership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMembership(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
    );
  }

  @override
  $CachedMembershipsTable createAlias(String alias) {
    return $CachedMembershipsTable(attachedDatabase, alias);
  }
}

class CachedMembership extends DataClass
    implements Insertable<CachedMembership> {
  final String tenantId;
  final String name;
  final String slug;
  final String role;
  final String currency;
  final String timezone;
  final int sortIndex;
  const CachedMembership({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.role,
    required this.currency,
    required this.timezone,
    required this.sortIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['name'] = Variable<String>(name);
    map['slug'] = Variable<String>(slug);
    map['role'] = Variable<String>(role);
    map['currency'] = Variable<String>(currency);
    map['timezone'] = Variable<String>(timezone);
    map['sort_index'] = Variable<int>(sortIndex);
    return map;
  }

  CachedMembershipsCompanion toCompanion(bool nullToAbsent) {
    return CachedMembershipsCompanion(
      tenantId: Value(tenantId),
      name: Value(name),
      slug: Value(slug),
      role: Value(role),
      currency: Value(currency),
      timezone: Value(timezone),
      sortIndex: Value(sortIndex),
    );
  }

  factory CachedMembership.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMembership(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      name: serializer.fromJson<String>(json['name']),
      slug: serializer.fromJson<String>(json['slug']),
      role: serializer.fromJson<String>(json['role']),
      currency: serializer.fromJson<String>(json['currency']),
      timezone: serializer.fromJson<String>(json['timezone']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'name': serializer.toJson<String>(name),
      'slug': serializer.toJson<String>(slug),
      'role': serializer.toJson<String>(role),
      'currency': serializer.toJson<String>(currency),
      'timezone': serializer.toJson<String>(timezone),
      'sortIndex': serializer.toJson<int>(sortIndex),
    };
  }

  CachedMembership copyWith({
    String? tenantId,
    String? name,
    String? slug,
    String? role,
    String? currency,
    String? timezone,
    int? sortIndex,
  }) => CachedMembership(
    tenantId: tenantId ?? this.tenantId,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    role: role ?? this.role,
    currency: currency ?? this.currency,
    timezone: timezone ?? this.timezone,
    sortIndex: sortIndex ?? this.sortIndex,
  );
  CachedMembership copyWithCompanion(CachedMembershipsCompanion data) {
    return CachedMembership(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      name: data.name.present ? data.name.value : this.name,
      slug: data.slug.present ? data.slug.value : this.slug,
      role: data.role.present ? data.role.value : this.role,
      currency: data.currency.present ? data.currency.value : this.currency,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMembership(')
          ..write('tenantId: $tenantId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('role: $role, ')
          ..write('currency: $currency, ')
          ..write('timezone: $timezone, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(tenantId, name, slug, role, currency, timezone, sortIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMembership &&
          other.tenantId == this.tenantId &&
          other.name == this.name &&
          other.slug == this.slug &&
          other.role == this.role &&
          other.currency == this.currency &&
          other.timezone == this.timezone &&
          other.sortIndex == this.sortIndex);
}

class CachedMembershipsCompanion extends UpdateCompanion<CachedMembership> {
  final Value<String> tenantId;
  final Value<String> name;
  final Value<String> slug;
  final Value<String> role;
  final Value<String> currency;
  final Value<String> timezone;
  final Value<int> sortIndex;
  final Value<int> rowid;
  const CachedMembershipsCompanion({
    this.tenantId = const Value.absent(),
    this.name = const Value.absent(),
    this.slug = const Value.absent(),
    this.role = const Value.absent(),
    this.currency = const Value.absent(),
    this.timezone = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMembershipsCompanion.insert({
    required String tenantId,
    required String name,
    required String slug,
    required String role,
    required String currency,
    required String timezone,
    required int sortIndex,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       name = Value(name),
       slug = Value(slug),
       role = Value(role),
       currency = Value(currency),
       timezone = Value(timezone),
       sortIndex = Value(sortIndex);
  static Insertable<CachedMembership> custom({
    Expression<String>? tenantId,
    Expression<String>? name,
    Expression<String>? slug,
    Expression<String>? role,
    Expression<String>? currency,
    Expression<String>? timezone,
    Expression<int>? sortIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
      if (role != null) 'role': role,
      if (currency != null) 'currency': currency,
      if (timezone != null) 'timezone': timezone,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMembershipsCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? name,
    Value<String>? slug,
    Value<String>? role,
    Value<String>? currency,
    Value<String>? timezone,
    Value<int>? sortIndex,
    Value<int>? rowid,
  }) {
    return CachedMembershipsCompanion(
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      role: role ?? this.role,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      sortIndex: sortIndex ?? this.sortIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMembershipsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('role: $role, ')
          ..write('currency: $currency, ')
          ..write('timezone: $timezone, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPermissionsTable extends CachedPermissions
    with TableInfo<$CachedPermissionsTable, CachedPermission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPermissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tenantId, key];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_permissions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPermission> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, key};
  @override
  CachedPermission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPermission(
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
    );
  }

  @override
  $CachedPermissionsTable createAlias(String alias) {
    return $CachedPermissionsTable(attachedDatabase, alias);
  }
}

class CachedPermission extends DataClass
    implements Insertable<CachedPermission> {
  final String tenantId;
  final String key;
  const CachedPermission({required this.tenantId, required this.key});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['key'] = Variable<String>(key);
    return map;
  }

  CachedPermissionsCompanion toCompanion(bool nullToAbsent) {
    return CachedPermissionsCompanion(
      tenantId: Value(tenantId),
      key: Value(key),
    );
  }

  factory CachedPermission.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPermission(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      key: serializer.fromJson<String>(json['key']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'key': serializer.toJson<String>(key),
    };
  }

  CachedPermission copyWith({String? tenantId, String? key}) =>
      CachedPermission(
        tenantId: tenantId ?? this.tenantId,
        key: key ?? this.key,
      );
  CachedPermission copyWithCompanion(CachedPermissionsCompanion data) {
    return CachedPermission(
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      key: data.key.present ? data.key.value : this.key,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPermission(')
          ..write('tenantId: $tenantId, ')
          ..write('key: $key')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, key);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPermission &&
          other.tenantId == this.tenantId &&
          other.key == this.key);
}

class CachedPermissionsCompanion extends UpdateCompanion<CachedPermission> {
  final Value<String> tenantId;
  final Value<String> key;
  final Value<int> rowid;
  const CachedPermissionsCompanion({
    this.tenantId = const Value.absent(),
    this.key = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPermissionsCompanion.insert({
    required String tenantId,
    required String key,
    this.rowid = const Value.absent(),
  }) : tenantId = Value(tenantId),
       key = Value(key);
  static Insertable<CachedPermission> custom({
    Expression<String>? tenantId,
    Expression<String>? key,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (key != null) 'key': key,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPermissionsCompanion copyWith({
    Value<String>? tenantId,
    Value<String>? key,
    Value<int>? rowid,
  }) {
    return CachedPermissionsCompanion(
      tenantId: tenantId ?? this.tenantId,
      key: key ?? this.key,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPermissionsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('key: $key, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxRowsTable extends OutboxRows
    with TableInfo<$OutboxRowsTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderRefMeta = const VerificationMeta(
    'orderRef',
  );
  @override
  late final GeneratedColumn<String> orderRef = GeneratedColumn<String>(
    'order_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tenantId,
    kind,
    orderRef,
    payloadJson,
    idempotencyKey,
    attempts,
    state,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('order_ref')) {
      context.handle(
        _orderRefMeta,
        orderRef.isAcceptableOrUnknown(data['order_ref']!, _orderRefMeta),
      );
    } else if (isInserting) {
      context.missing(_orderRefMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      orderRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_ref'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxRowsTable createAlias(String alias) {
    return $OutboxRowsTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int id;
  final String tenantId;
  final String kind;
  final String orderRef;
  final String payloadJson;

  /// Unique: a double-enqueue must collapse to one row, or one tap becomes two
  /// orders.
  final String idempotencyKey;
  final int attempts;
  final String state;
  final String? lastError;
  final DateTime createdAt;
  const OutboxRow({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.orderRef,
    required this.payloadJson,
    required this.idempotencyKey,
    required this.attempts,
    required this.state,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['kind'] = Variable<String>(kind);
    map['order_ref'] = Variable<String>(orderRef);
    map['payload_json'] = Variable<String>(payloadJson);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['attempts'] = Variable<int>(attempts);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return OutboxRowsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      kind: Value(kind),
      orderRef: Value(orderRef),
      payloadJson: Value(payloadJson),
      idempotencyKey: Value(idempotencyKey),
      attempts: Value(attempts),
      state: Value(state),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      id: serializer.fromJson<int>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      kind: serializer.fromJson<String>(json['kind']),
      orderRef: serializer.fromJson<String>(json['orderRef']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      attempts: serializer.fromJson<int>(json['attempts']),
      state: serializer.fromJson<String>(json['state']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'kind': serializer.toJson<String>(kind),
      'orderRef': serializer.toJson<String>(orderRef),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'attempts': serializer.toJson<int>(attempts),
      'state': serializer.toJson<String>(state),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxRow copyWith({
    int? id,
    String? tenantId,
    String? kind,
    String? orderRef,
    String? payloadJson,
    String? idempotencyKey,
    int? attempts,
    String? state,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => OutboxRow(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    kind: kind ?? this.kind,
    orderRef: orderRef ?? this.orderRef,
    payloadJson: payloadJson ?? this.payloadJson,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    attempts: attempts ?? this.attempts,
    state: state ?? this.state,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxRow copyWithCompanion(OutboxRowsCompanion data) {
    return OutboxRow(
      id: data.id.present ? data.id.value : this.id,
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      kind: data.kind.present ? data.kind.value : this.kind,
      orderRef: data.orderRef.present ? data.orderRef.value : this.orderRef,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      state: data.state.present ? data.state.value : this.state,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('kind: $kind, ')
          ..write('orderRef: $orderRef, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('attempts: $attempts, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    kind,
    orderRef,
    payloadJson,
    idempotencyKey,
    attempts,
    state,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.kind == this.kind &&
          other.orderRef == this.orderRef &&
          other.payloadJson == this.payloadJson &&
          other.idempotencyKey == this.idempotencyKey &&
          other.attempts == this.attempts &&
          other.state == this.state &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class OutboxRowsCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> id;
  final Value<String> tenantId;
  final Value<String> kind;
  final Value<String> orderRef;
  final Value<String> payloadJson;
  final Value<String> idempotencyKey;
  final Value<int> attempts;
  final Value<String> state;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  const OutboxRowsCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.kind = const Value.absent(),
    this.orderRef = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.attempts = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxRowsCompanion.insert({
    this.id = const Value.absent(),
    required String tenantId,
    required String kind,
    required String orderRef,
    required String payloadJson,
    required String idempotencyKey,
    this.attempts = const Value.absent(),
    required String state,
    this.lastError = const Value.absent(),
    required DateTime createdAt,
  }) : tenantId = Value(tenantId),
       kind = Value(kind),
       orderRef = Value(orderRef),
       payloadJson = Value(payloadJson),
       idempotencyKey = Value(idempotencyKey),
       state = Value(state),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<int>? id,
    Expression<String>? tenantId,
    Expression<String>? kind,
    Expression<String>? orderRef,
    Expression<String>? payloadJson,
    Expression<String>? idempotencyKey,
    Expression<int>? attempts,
    Expression<String>? state,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (kind != null) 'kind': kind,
      if (orderRef != null) 'order_ref': orderRef,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (attempts != null) 'attempts': attempts,
      if (state != null) 'state': state,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? tenantId,
    Value<String>? kind,
    Value<String>? orderRef,
    Value<String>? payloadJson,
    Value<String>? idempotencyKey,
    Value<int>? attempts,
    Value<String>? state,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
  }) {
    return OutboxRowsCompanion(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      kind: kind ?? this.kind,
      orderRef: orderRef ?? this.orderRef,
      payloadJson: payloadJson ?? this.payloadJson,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      attempts: attempts ?? this.attempts,
      state: state ?? this.state,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (orderRef.present) {
      map['order_ref'] = Variable<String>(orderRef.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRowsCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('kind: $kind, ')
          ..write('orderRef: $orderRef, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('attempts: $attempts, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CacheMetaTable cacheMeta = $CacheMetaTable(this);
  late final $CachedCategoriesTable cachedCategories = $CachedCategoriesTable(
    this,
  );
  late final $CachedMenuItemsTable cachedMenuItems = $CachedMenuItemsTable(
    this,
  );
  late final $CachedVariantsTable cachedVariants = $CachedVariantsTable(this);
  late final $CachedModifiersTable cachedModifiers = $CachedModifiersTable(
    this,
  );
  late final $CachedItemModifiersTable cachedItemModifiers =
      $CachedItemModifiersTable(this);
  late final $CachedFloorsTable cachedFloors = $CachedFloorsTable(this);
  late final $CachedTablesTable cachedTables = $CachedTablesTable(this);
  late final $CachedMembershipsTable cachedMemberships =
      $CachedMembershipsTable(this);
  late final $CachedPermissionsTable cachedPermissions =
      $CachedPermissionsTable(this);
  late final $OutboxRowsTable outboxRows = $OutboxRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cacheMeta,
    cachedCategories,
    cachedMenuItems,
    cachedVariants,
    cachedModifiers,
    cachedItemModifiers,
    cachedFloors,
    cachedTables,
    cachedMemberships,
    cachedPermissions,
    outboxRows,
  ];
}

typedef $$CacheMetaTableCreateCompanionBuilder =
    CacheMetaCompanion Function({
      required String tenantId,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CacheMetaTableUpdateCompanionBuilder =
    CacheMetaCompanion Function({
      Value<String> tenantId,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CacheMetaTableFilterComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CacheMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheMetaTable,
          CacheMetaData,
          $$CacheMetaTableFilterComposer,
          $$CacheMetaTableOrderingComposer,
          $$CacheMetaTableAnnotationComposer,
          $$CacheMetaTableCreateCompanionBuilder,
          $$CacheMetaTableUpdateCompanionBuilder,
          (
            CacheMetaData,
            BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>,
          ),
          CacheMetaData,
          PrefetchHooks Function()
        > {
  $$CacheMetaTableTableManager(_$AppDatabase db, $CacheMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheMetaCompanion(
                tenantId: tenantId,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheMetaCompanion.insert(
                tenantId: tenantId,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheMetaTable,
      CacheMetaData,
      $$CacheMetaTableFilterComposer,
      $$CacheMetaTableOrderingComposer,
      $$CacheMetaTableAnnotationComposer,
      $$CacheMetaTableCreateCompanionBuilder,
      $$CacheMetaTableUpdateCompanionBuilder,
      (
        CacheMetaData,
        BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>,
      ),
      CacheMetaData,
      PrefetchHooks Function()
    >;
typedef $$CachedCategoriesTableCreateCompanionBuilder =
    CachedCategoriesCompanion Function({
      required String tenantId,
      required String id,
      required String name,
      required int sort,
      Value<int> rowid,
    });
typedef $$CachedCategoriesTableUpdateCompanionBuilder =
    CachedCategoriesCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> name,
      Value<int> sort,
      Value<int> rowid,
    });

class $$CachedCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedCategoriesTable> {
  $$CachedCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedCategoriesTable> {
  $$CachedCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedCategoriesTable> {
  $$CachedCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$CachedCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedCategoriesTable,
          CachedCategory,
          $$CachedCategoriesTableFilterComposer,
          $$CachedCategoriesTableOrderingComposer,
          $$CachedCategoriesTableAnnotationComposer,
          $$CachedCategoriesTableCreateCompanionBuilder,
          $$CachedCategoriesTableUpdateCompanionBuilder,
          (
            CachedCategory,
            BaseReferences<
              _$AppDatabase,
              $CachedCategoriesTable,
              CachedCategory
            >,
          ),
          CachedCategory,
          PrefetchHooks Function()
        > {
  $$CachedCategoriesTableTableManager(
    _$AppDatabase db,
    $CachedCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCategoriesCompanion(
                tenantId: tenantId,
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String name,
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => CachedCategoriesCompanion.insert(
                tenantId: tenantId,
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedCategoriesTable,
      CachedCategory,
      $$CachedCategoriesTableFilterComposer,
      $$CachedCategoriesTableOrderingComposer,
      $$CachedCategoriesTableAnnotationComposer,
      $$CachedCategoriesTableCreateCompanionBuilder,
      $$CachedCategoriesTableUpdateCompanionBuilder,
      (
        CachedCategory,
        BaseReferences<_$AppDatabase, $CachedCategoriesTable, CachedCategory>,
      ),
      CachedCategory,
      PrefetchHooks Function()
    >;
typedef $$CachedMenuItemsTableCreateCompanionBuilder =
    CachedMenuItemsCompanion Function({
      required String tenantId,
      required String id,
      required String name,
      required int basePriceCents,
      Value<String?> categoryId,
      required bool is86,
      Value<bool?> isVeg,
      Value<String?> imageUrl,
      Value<int> rowid,
    });
typedef $$CachedMenuItemsTableUpdateCompanionBuilder =
    CachedMenuItemsCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> name,
      Value<int> basePriceCents,
      Value<String?> categoryId,
      Value<bool> is86,
      Value<bool?> isVeg,
      Value<String?> imageUrl,
      Value<int> rowid,
    });

class $$CachedMenuItemsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMenuItemsTable> {
  $$CachedMenuItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get basePriceCents => $composableBuilder(
    column: $table.basePriceCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get is86 => $composableBuilder(
    column: $table.is86,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVeg => $composableBuilder(
    column: $table.isVeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMenuItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMenuItemsTable> {
  $$CachedMenuItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get basePriceCents => $composableBuilder(
    column: $table.basePriceCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get is86 => $composableBuilder(
    column: $table.is86,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVeg => $composableBuilder(
    column: $table.isVeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMenuItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMenuItemsTable> {
  $$CachedMenuItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get basePriceCents => $composableBuilder(
    column: $table.basePriceCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get is86 =>
      $composableBuilder(column: $table.is86, builder: (column) => column);

  GeneratedColumn<bool> get isVeg =>
      $composableBuilder(column: $table.isVeg, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);
}

class $$CachedMenuItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMenuItemsTable,
          CachedMenuItem,
          $$CachedMenuItemsTableFilterComposer,
          $$CachedMenuItemsTableOrderingComposer,
          $$CachedMenuItemsTableAnnotationComposer,
          $$CachedMenuItemsTableCreateCompanionBuilder,
          $$CachedMenuItemsTableUpdateCompanionBuilder,
          (
            CachedMenuItem,
            BaseReferences<
              _$AppDatabase,
              $CachedMenuItemsTable,
              CachedMenuItem
            >,
          ),
          CachedMenuItem,
          PrefetchHooks Function()
        > {
  $$CachedMenuItemsTableTableManager(
    _$AppDatabase db,
    $CachedMenuItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMenuItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMenuItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMenuItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> basePriceCents = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<bool> is86 = const Value.absent(),
                Value<bool?> isVeg = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMenuItemsCompanion(
                tenantId: tenantId,
                id: id,
                name: name,
                basePriceCents: basePriceCents,
                categoryId: categoryId,
                is86: is86,
                isVeg: isVeg,
                imageUrl: imageUrl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String name,
                required int basePriceCents,
                Value<String?> categoryId = const Value.absent(),
                required bool is86,
                Value<bool?> isVeg = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMenuItemsCompanion.insert(
                tenantId: tenantId,
                id: id,
                name: name,
                basePriceCents: basePriceCents,
                categoryId: categoryId,
                is86: is86,
                isVeg: isVeg,
                imageUrl: imageUrl,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMenuItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMenuItemsTable,
      CachedMenuItem,
      $$CachedMenuItemsTableFilterComposer,
      $$CachedMenuItemsTableOrderingComposer,
      $$CachedMenuItemsTableAnnotationComposer,
      $$CachedMenuItemsTableCreateCompanionBuilder,
      $$CachedMenuItemsTableUpdateCompanionBuilder,
      (
        CachedMenuItem,
        BaseReferences<_$AppDatabase, $CachedMenuItemsTable, CachedMenuItem>,
      ),
      CachedMenuItem,
      PrefetchHooks Function()
    >;
typedef $$CachedVariantsTableCreateCompanionBuilder =
    CachedVariantsCompanion Function({
      required String tenantId,
      required String id,
      required String itemId,
      required String name,
      required int priceDeltaCents,
      Value<int> rowid,
    });
typedef $$CachedVariantsTableUpdateCompanionBuilder =
    CachedVariantsCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> itemId,
      Value<String> name,
      Value<int> priceDeltaCents,
      Value<int> rowid,
    });

class $$CachedVariantsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedVariantsTable> {
  $$CachedVariantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceDeltaCents => $composableBuilder(
    column: $table.priceDeltaCents,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedVariantsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedVariantsTable> {
  $$CachedVariantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceDeltaCents => $composableBuilder(
    column: $table.priceDeltaCents,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedVariantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedVariantsTable> {
  $$CachedVariantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get priceDeltaCents => $composableBuilder(
    column: $table.priceDeltaCents,
    builder: (column) => column,
  );
}

class $$CachedVariantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedVariantsTable,
          CachedVariant,
          $$CachedVariantsTableFilterComposer,
          $$CachedVariantsTableOrderingComposer,
          $$CachedVariantsTableAnnotationComposer,
          $$CachedVariantsTableCreateCompanionBuilder,
          $$CachedVariantsTableUpdateCompanionBuilder,
          (
            CachedVariant,
            BaseReferences<_$AppDatabase, $CachedVariantsTable, CachedVariant>,
          ),
          CachedVariant,
          PrefetchHooks Function()
        > {
  $$CachedVariantsTableTableManager(
    _$AppDatabase db,
    $CachedVariantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> priceDeltaCents = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedVariantsCompanion(
                tenantId: tenantId,
                id: id,
                itemId: itemId,
                name: name,
                priceDeltaCents: priceDeltaCents,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String itemId,
                required String name,
                required int priceDeltaCents,
                Value<int> rowid = const Value.absent(),
              }) => CachedVariantsCompanion.insert(
                tenantId: tenantId,
                id: id,
                itemId: itemId,
                name: name,
                priceDeltaCents: priceDeltaCents,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedVariantsTable,
      CachedVariant,
      $$CachedVariantsTableFilterComposer,
      $$CachedVariantsTableOrderingComposer,
      $$CachedVariantsTableAnnotationComposer,
      $$CachedVariantsTableCreateCompanionBuilder,
      $$CachedVariantsTableUpdateCompanionBuilder,
      (
        CachedVariant,
        BaseReferences<_$AppDatabase, $CachedVariantsTable, CachedVariant>,
      ),
      CachedVariant,
      PrefetchHooks Function()
    >;
typedef $$CachedModifiersTableCreateCompanionBuilder =
    CachedModifiersCompanion Function({
      required String tenantId,
      required String id,
      required String name,
      required int priceCents,
      Value<int> rowid,
    });
typedef $$CachedModifiersTableUpdateCompanionBuilder =
    CachedModifiersCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> name,
      Value<int> priceCents,
      Value<int> rowid,
    });

class $$CachedModifiersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedModifiersTable> {
  $$CachedModifiersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceCents => $composableBuilder(
    column: $table.priceCents,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedModifiersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedModifiersTable> {
  $$CachedModifiersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceCents => $composableBuilder(
    column: $table.priceCents,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedModifiersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedModifiersTable> {
  $$CachedModifiersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get priceCents => $composableBuilder(
    column: $table.priceCents,
    builder: (column) => column,
  );
}

class $$CachedModifiersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedModifiersTable,
          CachedModifier,
          $$CachedModifiersTableFilterComposer,
          $$CachedModifiersTableOrderingComposer,
          $$CachedModifiersTableAnnotationComposer,
          $$CachedModifiersTableCreateCompanionBuilder,
          $$CachedModifiersTableUpdateCompanionBuilder,
          (
            CachedModifier,
            BaseReferences<
              _$AppDatabase,
              $CachedModifiersTable,
              CachedModifier
            >,
          ),
          CachedModifier,
          PrefetchHooks Function()
        > {
  $$CachedModifiersTableTableManager(
    _$AppDatabase db,
    $CachedModifiersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedModifiersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedModifiersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedModifiersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> priceCents = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedModifiersCompanion(
                tenantId: tenantId,
                id: id,
                name: name,
                priceCents: priceCents,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String name,
                required int priceCents,
                Value<int> rowid = const Value.absent(),
              }) => CachedModifiersCompanion.insert(
                tenantId: tenantId,
                id: id,
                name: name,
                priceCents: priceCents,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedModifiersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedModifiersTable,
      CachedModifier,
      $$CachedModifiersTableFilterComposer,
      $$CachedModifiersTableOrderingComposer,
      $$CachedModifiersTableAnnotationComposer,
      $$CachedModifiersTableCreateCompanionBuilder,
      $$CachedModifiersTableUpdateCompanionBuilder,
      (
        CachedModifier,
        BaseReferences<_$AppDatabase, $CachedModifiersTable, CachedModifier>,
      ),
      CachedModifier,
      PrefetchHooks Function()
    >;
typedef $$CachedItemModifiersTableCreateCompanionBuilder =
    CachedItemModifiersCompanion Function({
      required String tenantId,
      required String itemId,
      required String modifierId,
      Value<int> rowid,
    });
typedef $$CachedItemModifiersTableUpdateCompanionBuilder =
    CachedItemModifiersCompanion Function({
      Value<String> tenantId,
      Value<String> itemId,
      Value<String> modifierId,
      Value<int> rowid,
    });

class $$CachedItemModifiersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedItemModifiersTable> {
  $$CachedItemModifiersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modifierId => $composableBuilder(
    column: $table.modifierId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedItemModifiersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedItemModifiersTable> {
  $$CachedItemModifiersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modifierId => $composableBuilder(
    column: $table.modifierId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedItemModifiersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedItemModifiersTable> {
  $$CachedItemModifiersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get modifierId => $composableBuilder(
    column: $table.modifierId,
    builder: (column) => column,
  );
}

class $$CachedItemModifiersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedItemModifiersTable,
          CachedItemModifier,
          $$CachedItemModifiersTableFilterComposer,
          $$CachedItemModifiersTableOrderingComposer,
          $$CachedItemModifiersTableAnnotationComposer,
          $$CachedItemModifiersTableCreateCompanionBuilder,
          $$CachedItemModifiersTableUpdateCompanionBuilder,
          (
            CachedItemModifier,
            BaseReferences<
              _$AppDatabase,
              $CachedItemModifiersTable,
              CachedItemModifier
            >,
          ),
          CachedItemModifier,
          PrefetchHooks Function()
        > {
  $$CachedItemModifiersTableTableManager(
    _$AppDatabase db,
    $CachedItemModifiersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedItemModifiersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedItemModifiersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedItemModifiersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> modifierId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedItemModifiersCompanion(
                tenantId: tenantId,
                itemId: itemId,
                modifierId: modifierId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String itemId,
                required String modifierId,
                Value<int> rowid = const Value.absent(),
              }) => CachedItemModifiersCompanion.insert(
                tenantId: tenantId,
                itemId: itemId,
                modifierId: modifierId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedItemModifiersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedItemModifiersTable,
      CachedItemModifier,
      $$CachedItemModifiersTableFilterComposer,
      $$CachedItemModifiersTableOrderingComposer,
      $$CachedItemModifiersTableAnnotationComposer,
      $$CachedItemModifiersTableCreateCompanionBuilder,
      $$CachedItemModifiersTableUpdateCompanionBuilder,
      (
        CachedItemModifier,
        BaseReferences<
          _$AppDatabase,
          $CachedItemModifiersTable,
          CachedItemModifier
        >,
      ),
      CachedItemModifier,
      PrefetchHooks Function()
    >;
typedef $$CachedFloorsTableCreateCompanionBuilder =
    CachedFloorsCompanion Function({
      required String tenantId,
      required String id,
      required String name,
      required int sort,
      Value<int> rowid,
    });
typedef $$CachedFloorsTableUpdateCompanionBuilder =
    CachedFloorsCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> name,
      Value<int> sort,
      Value<int> rowid,
    });

class $$CachedFloorsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedFloorsTable> {
  $$CachedFloorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFloorsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedFloorsTable> {
  $$CachedFloorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFloorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedFloorsTable> {
  $$CachedFloorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$CachedFloorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedFloorsTable,
          CachedFloor,
          $$CachedFloorsTableFilterComposer,
          $$CachedFloorsTableOrderingComposer,
          $$CachedFloorsTableAnnotationComposer,
          $$CachedFloorsTableCreateCompanionBuilder,
          $$CachedFloorsTableUpdateCompanionBuilder,
          (
            CachedFloor,
            BaseReferences<_$AppDatabase, $CachedFloorsTable, CachedFloor>,
          ),
          CachedFloor,
          PrefetchHooks Function()
        > {
  $$CachedFloorsTableTableManager(_$AppDatabase db, $CachedFloorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFloorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedFloorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedFloorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFloorsCompanion(
                tenantId: tenantId,
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String name,
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => CachedFloorsCompanion.insert(
                tenantId: tenantId,
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFloorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedFloorsTable,
      CachedFloor,
      $$CachedFloorsTableFilterComposer,
      $$CachedFloorsTableOrderingComposer,
      $$CachedFloorsTableAnnotationComposer,
      $$CachedFloorsTableCreateCompanionBuilder,
      $$CachedFloorsTableUpdateCompanionBuilder,
      (
        CachedFloor,
        BaseReferences<_$AppDatabase, $CachedFloorsTable, CachedFloor>,
      ),
      CachedFloor,
      PrefetchHooks Function()
    >;
typedef $$CachedTablesTableCreateCompanionBuilder =
    CachedTablesCompanion Function({
      required String tenantId,
      required String id,
      required String label,
      required int capacity,
      required String state,
      Value<String?> floorId,
      Value<String?> currentOrderId,
      Value<int> rowid,
    });
typedef $$CachedTablesTableUpdateCompanionBuilder =
    CachedTablesCompanion Function({
      Value<String> tenantId,
      Value<String> id,
      Value<String> label,
      Value<int> capacity,
      Value<String> state,
      Value<String?> floorId,
      Value<String?> currentOrderId,
      Value<int> rowid,
    });

class $$CachedTablesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTablesTable> {
  $$CachedTablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floorId => $composableBuilder(
    column: $table.floorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentOrderId => $composableBuilder(
    column: $table.currentOrderId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedTablesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTablesTable> {
  $$CachedTablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floorId => $composableBuilder(
    column: $table.floorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentOrderId => $composableBuilder(
    column: $table.currentOrderId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedTablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTablesTable> {
  $$CachedTablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get capacity =>
      $composableBuilder(column: $table.capacity, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get floorId =>
      $composableBuilder(column: $table.floorId, builder: (column) => column);

  GeneratedColumn<String> get currentOrderId => $composableBuilder(
    column: $table.currentOrderId,
    builder: (column) => column,
  );
}

class $$CachedTablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedTablesTable,
          CachedTable,
          $$CachedTablesTableFilterComposer,
          $$CachedTablesTableOrderingComposer,
          $$CachedTablesTableAnnotationComposer,
          $$CachedTablesTableCreateCompanionBuilder,
          $$CachedTablesTableUpdateCompanionBuilder,
          (
            CachedTable,
            BaseReferences<_$AppDatabase, $CachedTablesTable, CachedTable>,
          ),
          CachedTable,
          PrefetchHooks Function()
        > {
  $$CachedTablesTableTableManager(_$AppDatabase db, $CachedTablesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTablesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTablesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> capacity = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> floorId = const Value.absent(),
                Value<String?> currentOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedTablesCompanion(
                tenantId: tenantId,
                id: id,
                label: label,
                capacity: capacity,
                state: state,
                floorId: floorId,
                currentOrderId: currentOrderId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String id,
                required String label,
                required int capacity,
                required String state,
                Value<String?> floorId = const Value.absent(),
                Value<String?> currentOrderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedTablesCompanion.insert(
                tenantId: tenantId,
                id: id,
                label: label,
                capacity: capacity,
                state: state,
                floorId: floorId,
                currentOrderId: currentOrderId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedTablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedTablesTable,
      CachedTable,
      $$CachedTablesTableFilterComposer,
      $$CachedTablesTableOrderingComposer,
      $$CachedTablesTableAnnotationComposer,
      $$CachedTablesTableCreateCompanionBuilder,
      $$CachedTablesTableUpdateCompanionBuilder,
      (
        CachedTable,
        BaseReferences<_$AppDatabase, $CachedTablesTable, CachedTable>,
      ),
      CachedTable,
      PrefetchHooks Function()
    >;
typedef $$CachedMembershipsTableCreateCompanionBuilder =
    CachedMembershipsCompanion Function({
      required String tenantId,
      required String name,
      required String slug,
      required String role,
      required String currency,
      required String timezone,
      required int sortIndex,
      Value<int> rowid,
    });
typedef $$CachedMembershipsTableUpdateCompanionBuilder =
    CachedMembershipsCompanion Function({
      Value<String> tenantId,
      Value<String> name,
      Value<String> slug,
      Value<String> role,
      Value<String> currency,
      Value<String> timezone,
      Value<int> sortIndex,
      Value<int> rowid,
    });

class $$CachedMembershipsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMembershipsTable> {
  $$CachedMembershipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMembershipsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMembershipsTable> {
  $$CachedMembershipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMembershipsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMembershipsTable> {
  $$CachedMembershipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);
}

class $$CachedMembershipsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMembershipsTable,
          CachedMembership,
          $$CachedMembershipsTableFilterComposer,
          $$CachedMembershipsTableOrderingComposer,
          $$CachedMembershipsTableAnnotationComposer,
          $$CachedMembershipsTableCreateCompanionBuilder,
          $$CachedMembershipsTableUpdateCompanionBuilder,
          (
            CachedMembership,
            BaseReferences<
              _$AppDatabase,
              $CachedMembershipsTable,
              CachedMembership
            >,
          ),
          CachedMembership,
          PrefetchHooks Function()
        > {
  $$CachedMembershipsTableTableManager(
    _$AppDatabase db,
    $CachedMembershipsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMembershipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMembershipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMembershipsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMembershipsCompanion(
                tenantId: tenantId,
                name: name,
                slug: slug,
                role: role,
                currency: currency,
                timezone: timezone,
                sortIndex: sortIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String name,
                required String slug,
                required String role,
                required String currency,
                required String timezone,
                required int sortIndex,
                Value<int> rowid = const Value.absent(),
              }) => CachedMembershipsCompanion.insert(
                tenantId: tenantId,
                name: name,
                slug: slug,
                role: role,
                currency: currency,
                timezone: timezone,
                sortIndex: sortIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMembershipsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMembershipsTable,
      CachedMembership,
      $$CachedMembershipsTableFilterComposer,
      $$CachedMembershipsTableOrderingComposer,
      $$CachedMembershipsTableAnnotationComposer,
      $$CachedMembershipsTableCreateCompanionBuilder,
      $$CachedMembershipsTableUpdateCompanionBuilder,
      (
        CachedMembership,
        BaseReferences<
          _$AppDatabase,
          $CachedMembershipsTable,
          CachedMembership
        >,
      ),
      CachedMembership,
      PrefetchHooks Function()
    >;
typedef $$CachedPermissionsTableCreateCompanionBuilder =
    CachedPermissionsCompanion Function({
      required String tenantId,
      required String key,
      Value<int> rowid,
    });
typedef $$CachedPermissionsTableUpdateCompanionBuilder =
    CachedPermissionsCompanion Function({
      Value<String> tenantId,
      Value<String> key,
      Value<int> rowid,
    });

class $$CachedPermissionsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPermissionsTable> {
  $$CachedPermissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPermissionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPermissionsTable> {
  $$CachedPermissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPermissionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPermissionsTable> {
  $$CachedPermissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);
}

class $$CachedPermissionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedPermissionsTable,
          CachedPermission,
          $$CachedPermissionsTableFilterComposer,
          $$CachedPermissionsTableOrderingComposer,
          $$CachedPermissionsTableAnnotationComposer,
          $$CachedPermissionsTableCreateCompanionBuilder,
          $$CachedPermissionsTableUpdateCompanionBuilder,
          (
            CachedPermission,
            BaseReferences<
              _$AppDatabase,
              $CachedPermissionsTable,
              CachedPermission
            >,
          ),
          CachedPermission,
          PrefetchHooks Function()
        > {
  $$CachedPermissionsTableTableManager(
    _$AppDatabase db,
    $CachedPermissionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPermissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPermissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPermissionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tenantId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPermissionsCompanion(
                tenantId: tenantId,
                key: key,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tenantId,
                required String key,
                Value<int> rowid = const Value.absent(),
              }) => CachedPermissionsCompanion.insert(
                tenantId: tenantId,
                key: key,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPermissionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedPermissionsTable,
      CachedPermission,
      $$CachedPermissionsTableFilterComposer,
      $$CachedPermissionsTableOrderingComposer,
      $$CachedPermissionsTableAnnotationComposer,
      $$CachedPermissionsTableCreateCompanionBuilder,
      $$CachedPermissionsTableUpdateCompanionBuilder,
      (
        CachedPermission,
        BaseReferences<
          _$AppDatabase,
          $CachedPermissionsTable,
          CachedPermission
        >,
      ),
      CachedPermission,
      PrefetchHooks Function()
    >;
typedef $$OutboxRowsTableCreateCompanionBuilder =
    OutboxRowsCompanion Function({
      Value<int> id,
      required String tenantId,
      required String kind,
      required String orderRef,
      required String payloadJson,
      required String idempotencyKey,
      Value<int> attempts,
      required String state,
      Value<String?> lastError,
      required DateTime createdAt,
    });
typedef $$OutboxRowsTableUpdateCompanionBuilder =
    OutboxRowsCompanion Function({
      Value<int> id,
      Value<String> tenantId,
      Value<String> kind,
      Value<String> orderRef,
      Value<String> payloadJson,
      Value<String> idempotencyKey,
      Value<int> attempts,
      Value<String> state,
      Value<String?> lastError,
      Value<DateTime> createdAt,
    });

class $$OutboxRowsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderRef => $composableBuilder(
    column: $table.orderRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderRef => $composableBuilder(
    column: $table.orderRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get orderRef =>
      $composableBuilder(column: $table.orderRef, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxRowsTable,
          OutboxRow,
          $$OutboxRowsTableFilterComposer,
          $$OutboxRowsTableOrderingComposer,
          $$OutboxRowsTableAnnotationComposer,
          $$OutboxRowsTableCreateCompanionBuilder,
          $$OutboxRowsTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxRowsTableTableManager(_$AppDatabase db, $OutboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tenantId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> orderRef = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxRowsCompanion(
                id: id,
                tenantId: tenantId,
                kind: kind,
                orderRef: orderRef,
                payloadJson: payloadJson,
                idempotencyKey: idempotencyKey,
                attempts: attempts,
                state: state,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tenantId,
                required String kind,
                required String orderRef,
                required String payloadJson,
                required String idempotencyKey,
                Value<int> attempts = const Value.absent(),
                required String state,
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
              }) => OutboxRowsCompanion.insert(
                id: id,
                tenantId: tenantId,
                kind: kind,
                orderRef: orderRef,
                payloadJson: payloadJson,
                idempotencyKey: idempotencyKey,
                attempts: attempts,
                state: state,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxRowsTable,
      OutboxRow,
      $$OutboxRowsTableFilterComposer,
      $$OutboxRowsTableOrderingComposer,
      $$OutboxRowsTableAnnotationComposer,
      $$OutboxRowsTableCreateCompanionBuilder,
      $$OutboxRowsTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CacheMetaTableTableManager get cacheMeta =>
      $$CacheMetaTableTableManager(_db, _db.cacheMeta);
  $$CachedCategoriesTableTableManager get cachedCategories =>
      $$CachedCategoriesTableTableManager(_db, _db.cachedCategories);
  $$CachedMenuItemsTableTableManager get cachedMenuItems =>
      $$CachedMenuItemsTableTableManager(_db, _db.cachedMenuItems);
  $$CachedVariantsTableTableManager get cachedVariants =>
      $$CachedVariantsTableTableManager(_db, _db.cachedVariants);
  $$CachedModifiersTableTableManager get cachedModifiers =>
      $$CachedModifiersTableTableManager(_db, _db.cachedModifiers);
  $$CachedItemModifiersTableTableManager get cachedItemModifiers =>
      $$CachedItemModifiersTableTableManager(_db, _db.cachedItemModifiers);
  $$CachedFloorsTableTableManager get cachedFloors =>
      $$CachedFloorsTableTableManager(_db, _db.cachedFloors);
  $$CachedTablesTableTableManager get cachedTables =>
      $$CachedTablesTableTableManager(_db, _db.cachedTables);
  $$CachedMembershipsTableTableManager get cachedMemberships =>
      $$CachedMembershipsTableTableManager(_db, _db.cachedMemberships);
  $$CachedPermissionsTableTableManager get cachedPermissions =>
      $$CachedPermissionsTableTableManager(_db, _db.cachedPermissions);
  $$OutboxRowsTableTableManager get outboxRows =>
      $$OutboxRowsTableTableManager(_db, _db.outboxRows);
}
