// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_database.dart';

// ignore_for_file: type=lint
class $StoredChunksTable extends StoredChunks
    with TableInfo<$StoredChunksTable, StoredChunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    check: () => ComparableExpr(ordinal).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineStartMeta = const VerificationMeta(
    'lineStart',
  );
  @override
  late final GeneratedColumn<int> lineStart = GeneratedColumn<int>(
    'line_start',
    aliasedName,
    false,
    check: () => ComparableExpr(lineStart).isBiggerOrEqualValue(1),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineEndMeta = const VerificationMeta(
    'lineEnd',
  );
  @override
  late final GeneratedColumn<int> lineEnd = GeneratedColumn<int>(
    'line_end',
    aliasedName,
    false,
    check: () => ComparableExpr(lineEnd).isBiggerOrEqual(lineStart),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ordinal,
    sourcePath,
    lineStart,
    lineEnd,
    content,
    type,
    metadataJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredChunk> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('line_start')) {
      context.handle(
        _lineStartMeta,
        lineStart.isAcceptableOrUnknown(data['line_start']!, _lineStartMeta),
      );
    } else if (isInserting) {
      context.missing(_lineStartMeta);
    }
    if (data.containsKey('line_end')) {
      context.handle(
        _lineEndMeta,
        lineEnd.isAcceptableOrUnknown(data['line_end']!, _lineEndMeta),
      );
    } else if (isInserting) {
      context.missing(_lineEndMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metadataJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredChunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredChunk(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      lineStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_start'],
      )!,
      lineEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_end'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      )!,
    );
  }

  @override
  $StoredChunksTable createAlias(String alias) {
    return $StoredChunksTable(attachedDatabase, alias);
  }
}

class StoredChunk extends DataClass implements Insertable<StoredChunk> {
  final String id;
  final int ordinal;
  final String sourcePath;
  final int lineStart;
  final int lineEnd;
  final String content;
  final String type;
  final String metadataJson;
  const StoredChunk({
    required this.id,
    required this.ordinal,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.content,
    required this.type,
    required this.metadataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['ordinal'] = Variable<int>(ordinal);
    map['source_path'] = Variable<String>(sourcePath);
    map['line_start'] = Variable<int>(lineStart);
    map['line_end'] = Variable<int>(lineEnd);
    map['content'] = Variable<String>(content);
    map['type'] = Variable<String>(type);
    map['metadata_json'] = Variable<String>(metadataJson);
    return map;
  }

  StoredChunksCompanion toCompanion(bool nullToAbsent) {
    return StoredChunksCompanion(
      id: Value(id),
      ordinal: Value(ordinal),
      sourcePath: Value(sourcePath),
      lineStart: Value(lineStart),
      lineEnd: Value(lineEnd),
      content: Value(content),
      type: Value(type),
      metadataJson: Value(metadataJson),
    );
  }

  factory StoredChunk.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredChunk(
      id: serializer.fromJson<String>(json['id']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      lineStart: serializer.fromJson<int>(json['lineStart']),
      lineEnd: serializer.fromJson<int>(json['lineEnd']),
      content: serializer.fromJson<String>(json['content']),
      type: serializer.fromJson<String>(json['type']),
      metadataJson: serializer.fromJson<String>(json['metadataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ordinal': serializer.toJson<int>(ordinal),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'lineStart': serializer.toJson<int>(lineStart),
      'lineEnd': serializer.toJson<int>(lineEnd),
      'content': serializer.toJson<String>(content),
      'type': serializer.toJson<String>(type),
      'metadataJson': serializer.toJson<String>(metadataJson),
    };
  }

  StoredChunk copyWith({
    String? id,
    int? ordinal,
    String? sourcePath,
    int? lineStart,
    int? lineEnd,
    String? content,
    String? type,
    String? metadataJson,
  }) => StoredChunk(
    id: id ?? this.id,
    ordinal: ordinal ?? this.ordinal,
    sourcePath: sourcePath ?? this.sourcePath,
    lineStart: lineStart ?? this.lineStart,
    lineEnd: lineEnd ?? this.lineEnd,
    content: content ?? this.content,
    type: type ?? this.type,
    metadataJson: metadataJson ?? this.metadataJson,
  );
  StoredChunk copyWithCompanion(StoredChunksCompanion data) {
    return StoredChunk(
      id: data.id.present ? data.id.value : this.id,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      lineStart: data.lineStart.present ? data.lineStart.value : this.lineStart,
      lineEnd: data.lineEnd.present ? data.lineEnd.value : this.lineEnd,
      content: data.content.present ? data.content.value : this.content,
      type: data.type.present ? data.type.value : this.type,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredChunk(')
          ..write('id: $id, ')
          ..write('ordinal: $ordinal, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('lineStart: $lineStart, ')
          ..write('lineEnd: $lineEnd, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ordinal,
    sourcePath,
    lineStart,
    lineEnd,
    content,
    type,
    metadataJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredChunk &&
          other.id == this.id &&
          other.ordinal == this.ordinal &&
          other.sourcePath == this.sourcePath &&
          other.lineStart == this.lineStart &&
          other.lineEnd == this.lineEnd &&
          other.content == this.content &&
          other.type == this.type &&
          other.metadataJson == this.metadataJson);
}

class StoredChunksCompanion extends UpdateCompanion<StoredChunk> {
  final Value<String> id;
  final Value<int> ordinal;
  final Value<String> sourcePath;
  final Value<int> lineStart;
  final Value<int> lineEnd;
  final Value<String> content;
  final Value<String> type;
  final Value<String> metadataJson;
  final Value<int> rowid;
  const StoredChunksCompanion({
    this.id = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.lineStart = const Value.absent(),
    this.lineEnd = const Value.absent(),
    this.content = const Value.absent(),
    this.type = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredChunksCompanion.insert({
    required String id,
    required int ordinal,
    required String sourcePath,
    required int lineStart,
    required int lineEnd,
    required String content,
    required String type,
    required String metadataJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ordinal = Value(ordinal),
       sourcePath = Value(sourcePath),
       lineStart = Value(lineStart),
       lineEnd = Value(lineEnd),
       content = Value(content),
       type = Value(type),
       metadataJson = Value(metadataJson);
  static Insertable<StoredChunk> custom({
    Expression<String>? id,
    Expression<int>? ordinal,
    Expression<String>? sourcePath,
    Expression<int>? lineStart,
    Expression<int>? lineEnd,
    Expression<String>? content,
    Expression<String>? type,
    Expression<String>? metadataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ordinal != null) 'ordinal': ordinal,
      if (sourcePath != null) 'source_path': sourcePath,
      if (lineStart != null) 'line_start': lineStart,
      if (lineEnd != null) 'line_end': lineEnd,
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredChunksCompanion copyWith({
    Value<String>? id,
    Value<int>? ordinal,
    Value<String>? sourcePath,
    Value<int>? lineStart,
    Value<int>? lineEnd,
    Value<String>? content,
    Value<String>? type,
    Value<String>? metadataJson,
    Value<int>? rowid,
  }) {
    return StoredChunksCompanion(
      id: id ?? this.id,
      ordinal: ordinal ?? this.ordinal,
      sourcePath: sourcePath ?? this.sourcePath,
      lineStart: lineStart ?? this.lineStart,
      lineEnd: lineEnd ?? this.lineEnd,
      content: content ?? this.content,
      type: type ?? this.type,
      metadataJson: metadataJson ?? this.metadataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (lineStart.present) {
      map['line_start'] = Variable<int>(lineStart.value);
    }
    if (lineEnd.present) {
      map['line_end'] = Variable<int>(lineEnd.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredChunksCompanion(')
          ..write('id: $id, ')
          ..write('ordinal: $ordinal, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('lineStart: $lineStart, ')
          ..write('lineEnd: $lineEnd, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredEmbeddingsTable extends StoredEmbeddings
    with TableInfo<$StoredEmbeddingsTable, StoredEmbedding> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredEmbeddingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chunkIdMeta = const VerificationMeta(
    'chunkId',
  );
  @override
  late final GeneratedColumn<String> chunkId = GeneratedColumn<String>(
    'chunk_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stored_chunks (id) ON DELETE CASCADE',
    ),
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
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dimensionMeta = const VerificationMeta(
    'dimension',
  );
  @override
  late final GeneratedColumn<int> dimension = GeneratedColumn<int>(
    'dimension',
    aliasedName,
    false,
    check: () => ComparableExpr(dimension).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vectorMeta = const VerificationMeta('vector');
  @override
  late final GeneratedColumn<Uint8List> vector = GeneratedColumn<Uint8List>(
    'vector',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    chunkId,
    source,
    model,
    dimension,
    vector,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_embeddings';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredEmbedding> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chunk_id')) {
      context.handle(
        _chunkIdMeta,
        chunkId.isAcceptableOrUnknown(data['chunk_id']!, _chunkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('dimension')) {
      context.handle(
        _dimensionMeta,
        dimension.isAcceptableOrUnknown(data['dimension']!, _dimensionMeta),
      );
    } else if (isInserting) {
      context.missing(_dimensionMeta);
    }
    if (data.containsKey('vector')) {
      context.handle(
        _vectorMeta,
        vector.isAcceptableOrUnknown(data['vector']!, _vectorMeta),
      );
    } else if (isInserting) {
      context.missing(_vectorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chunkId, source, model};
  @override
  StoredEmbedding map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredEmbedding(
      chunkId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chunk_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      dimension: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dimension'],
      )!,
      vector: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}vector'],
      )!,
    );
  }

  @override
  $StoredEmbeddingsTable createAlias(String alias) {
    return $StoredEmbeddingsTable(attachedDatabase, alias);
  }
}

class StoredEmbedding extends DataClass implements Insertable<StoredEmbedding> {
  final String chunkId;
  final String source;
  final String model;
  final int dimension;
  final Uint8List vector;
  const StoredEmbedding({
    required this.chunkId,
    required this.source,
    required this.model,
    required this.dimension,
    required this.vector,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chunk_id'] = Variable<String>(chunkId);
    map['source'] = Variable<String>(source);
    map['model'] = Variable<String>(model);
    map['dimension'] = Variable<int>(dimension);
    map['vector'] = Variable<Uint8List>(vector);
    return map;
  }

  StoredEmbeddingsCompanion toCompanion(bool nullToAbsent) {
    return StoredEmbeddingsCompanion(
      chunkId: Value(chunkId),
      source: Value(source),
      model: Value(model),
      dimension: Value(dimension),
      vector: Value(vector),
    );
  }

  factory StoredEmbedding.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredEmbedding(
      chunkId: serializer.fromJson<String>(json['chunkId']),
      source: serializer.fromJson<String>(json['source']),
      model: serializer.fromJson<String>(json['model']),
      dimension: serializer.fromJson<int>(json['dimension']),
      vector: serializer.fromJson<Uint8List>(json['vector']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chunkId': serializer.toJson<String>(chunkId),
      'source': serializer.toJson<String>(source),
      'model': serializer.toJson<String>(model),
      'dimension': serializer.toJson<int>(dimension),
      'vector': serializer.toJson<Uint8List>(vector),
    };
  }

  StoredEmbedding copyWith({
    String? chunkId,
    String? source,
    String? model,
    int? dimension,
    Uint8List? vector,
  }) => StoredEmbedding(
    chunkId: chunkId ?? this.chunkId,
    source: source ?? this.source,
    model: model ?? this.model,
    dimension: dimension ?? this.dimension,
    vector: vector ?? this.vector,
  );
  StoredEmbedding copyWithCompanion(StoredEmbeddingsCompanion data) {
    return StoredEmbedding(
      chunkId: data.chunkId.present ? data.chunkId.value : this.chunkId,
      source: data.source.present ? data.source.value : this.source,
      model: data.model.present ? data.model.value : this.model,
      dimension: data.dimension.present ? data.dimension.value : this.dimension,
      vector: data.vector.present ? data.vector.value : this.vector,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredEmbedding(')
          ..write('chunkId: $chunkId, ')
          ..write('source: $source, ')
          ..write('model: $model, ')
          ..write('dimension: $dimension, ')
          ..write('vector: $vector')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    chunkId,
    source,
    model,
    dimension,
    $driftBlobEquality.hash(vector),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredEmbedding &&
          other.chunkId == this.chunkId &&
          other.source == this.source &&
          other.model == this.model &&
          other.dimension == this.dimension &&
          $driftBlobEquality.equals(other.vector, this.vector));
}

class StoredEmbeddingsCompanion extends UpdateCompanion<StoredEmbedding> {
  final Value<String> chunkId;
  final Value<String> source;
  final Value<String> model;
  final Value<int> dimension;
  final Value<Uint8List> vector;
  final Value<int> rowid;
  const StoredEmbeddingsCompanion({
    this.chunkId = const Value.absent(),
    this.source = const Value.absent(),
    this.model = const Value.absent(),
    this.dimension = const Value.absent(),
    this.vector = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredEmbeddingsCompanion.insert({
    required String chunkId,
    required String source,
    required String model,
    required int dimension,
    required Uint8List vector,
    this.rowid = const Value.absent(),
  }) : chunkId = Value(chunkId),
       source = Value(source),
       model = Value(model),
       dimension = Value(dimension),
       vector = Value(vector);
  static Insertable<StoredEmbedding> custom({
    Expression<String>? chunkId,
    Expression<String>? source,
    Expression<String>? model,
    Expression<int>? dimension,
    Expression<Uint8List>? vector,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chunkId != null) 'chunk_id': chunkId,
      if (source != null) 'source': source,
      if (model != null) 'model': model,
      if (dimension != null) 'dimension': dimension,
      if (vector != null) 'vector': vector,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredEmbeddingsCompanion copyWith({
    Value<String>? chunkId,
    Value<String>? source,
    Value<String>? model,
    Value<int>? dimension,
    Value<Uint8List>? vector,
    Value<int>? rowid,
  }) {
    return StoredEmbeddingsCompanion(
      chunkId: chunkId ?? this.chunkId,
      source: source ?? this.source,
      model: model ?? this.model,
      dimension: dimension ?? this.dimension,
      vector: vector ?? this.vector,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chunkId.present) {
      map['chunk_id'] = Variable<String>(chunkId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (dimension.present) {
      map['dimension'] = Variable<int>(dimension.value);
    }
    if (vector.present) {
      map['vector'] = Variable<Uint8List>(vector.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredEmbeddingsCompanion(')
          ..write('chunkId: $chunkId, ')
          ..write('source: $source, ')
          ..write('model: $model, ')
          ..write('dimension: $dimension, ')
          ..write('vector: $vector, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GenerationRecordsTable extends GenerationRecords
    with TableInfo<$GenerationRecordsTable, GenerationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GenerationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => id.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordJsonMeta = const VerificationMeta(
    'recordJson',
  );
  @override
  late final GeneratedColumn<String> recordJson = GeneratedColumn<String>(
    'record_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, recordJson, checksum];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'generation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<GenerationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('record_json')) {
      context.handle(
        _recordJsonMeta,
        recordJson.isAcceptableOrUnknown(data['record_json']!, _recordJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_recordJsonMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GenerationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GenerationRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      recordJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_json'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
    );
  }

  @override
  $GenerationRecordsTable createAlias(String alias) {
    return $GenerationRecordsTable(attachedDatabase, alias);
  }
}

class GenerationRecord extends DataClass
    implements Insertable<GenerationRecord> {
  final int id;
  final String recordJson;
  final String checksum;
  const GenerationRecord({
    required this.id,
    required this.recordJson,
    required this.checksum,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['record_json'] = Variable<String>(recordJson);
    map['checksum'] = Variable<String>(checksum);
    return map;
  }

  GenerationRecordsCompanion toCompanion(bool nullToAbsent) {
    return GenerationRecordsCompanion(
      id: Value(id),
      recordJson: Value(recordJson),
      checksum: Value(checksum),
    );
  }

  factory GenerationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GenerationRecord(
      id: serializer.fromJson<int>(json['id']),
      recordJson: serializer.fromJson<String>(json['recordJson']),
      checksum: serializer.fromJson<String>(json['checksum']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'recordJson': serializer.toJson<String>(recordJson),
      'checksum': serializer.toJson<String>(checksum),
    };
  }

  GenerationRecord copyWith({int? id, String? recordJson, String? checksum}) =>
      GenerationRecord(
        id: id ?? this.id,
        recordJson: recordJson ?? this.recordJson,
        checksum: checksum ?? this.checksum,
      );
  GenerationRecord copyWithCompanion(GenerationRecordsCompanion data) {
    return GenerationRecord(
      id: data.id.present ? data.id.value : this.id,
      recordJson: data.recordJson.present
          ? data.recordJson.value
          : this.recordJson,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GenerationRecord(')
          ..write('id: $id, ')
          ..write('recordJson: $recordJson, ')
          ..write('checksum: $checksum')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, recordJson, checksum);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GenerationRecord &&
          other.id == this.id &&
          other.recordJson == this.recordJson &&
          other.checksum == this.checksum);
}

class GenerationRecordsCompanion extends UpdateCompanion<GenerationRecord> {
  final Value<int> id;
  final Value<String> recordJson;
  final Value<String> checksum;
  const GenerationRecordsCompanion({
    this.id = const Value.absent(),
    this.recordJson = const Value.absent(),
    this.checksum = const Value.absent(),
  });
  GenerationRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String recordJson,
    required String checksum,
  }) : recordJson = Value(recordJson),
       checksum = Value(checksum);
  static Insertable<GenerationRecord> custom({
    Expression<int>? id,
    Expression<String>? recordJson,
    Expression<String>? checksum,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordJson != null) 'record_json': recordJson,
      if (checksum != null) 'checksum': checksum,
    });
  }

  GenerationRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? recordJson,
    Value<String>? checksum,
  }) {
    return GenerationRecordsCompanion(
      id: id ?? this.id,
      recordJson: recordJson ?? this.recordJson,
      checksum: checksum ?? this.checksum,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (recordJson.present) {
      map['record_json'] = Variable<String>(recordJson.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GenerationRecordsCompanion(')
          ..write('id: $id, ')
          ..write('recordJson: $recordJson, ')
          ..write('checksum: $checksum')
          ..write(')'))
        .toString();
  }
}

abstract class _$StorageDatabase extends GeneratedDatabase {
  _$StorageDatabase(QueryExecutor e) : super(e);
  $StorageDatabaseManager get managers => $StorageDatabaseManager(this);
  late final $StoredChunksTable storedChunks = $StoredChunksTable(this);
  late final $StoredEmbeddingsTable storedEmbeddings = $StoredEmbeddingsTable(
    this,
  );
  late final $GenerationRecordsTable generationRecords =
      $GenerationRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storedChunks,
    storedEmbeddings,
    generationRecords,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'stored_chunks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('stored_embeddings', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$StoredChunksTableCreateCompanionBuilder =
    StoredChunksCompanion Function({
      required String id,
      required int ordinal,
      required String sourcePath,
      required int lineStart,
      required int lineEnd,
      required String content,
      required String type,
      required String metadataJson,
      Value<int> rowid,
    });
typedef $$StoredChunksTableUpdateCompanionBuilder =
    StoredChunksCompanion Function({
      Value<String> id,
      Value<int> ordinal,
      Value<String> sourcePath,
      Value<int> lineStart,
      Value<int> lineEnd,
      Value<String> content,
      Value<String> type,
      Value<String> metadataJson,
      Value<int> rowid,
    });

final class $$StoredChunksTableReferences
    extends BaseReferences<_$StorageDatabase, $StoredChunksTable, StoredChunk> {
  $$StoredChunksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$StoredEmbeddingsTable, List<StoredEmbedding>>
  _storedEmbeddingsRefsTable(_$StorageDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.storedEmbeddings,
        aliasName: 'stored_chunks__id__stored_embeddings__chunk_id',
      );

  $$StoredEmbeddingsTableProcessedTableManager get storedEmbeddingsRefs {
    final manager = $$StoredEmbeddingsTableTableManager(
      $_db,
      $_db.storedEmbeddings,
    ).filter((f) => f.chunkId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _storedEmbeddingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StoredChunksTableFilterComposer
    extends Composer<_$StorageDatabase, $StoredChunksTable> {
  $$StoredChunksTableFilterComposer({
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

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineStart => $composableBuilder(
    column: $table.lineStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineEnd => $composableBuilder(
    column: $table.lineEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> storedEmbeddingsRefs(
    Expression<bool> Function($$StoredEmbeddingsTableFilterComposer f) f,
  ) {
    final $$StoredEmbeddingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.storedEmbeddings,
      getReferencedColumn: (t) => t.chunkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredEmbeddingsTableFilterComposer(
            $db: $db,
            $table: $db.storedEmbeddings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StoredChunksTableOrderingComposer
    extends Composer<_$StorageDatabase, $StoredChunksTable> {
  $$StoredChunksTableOrderingComposer({
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

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineStart => $composableBuilder(
    column: $table.lineStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineEnd => $composableBuilder(
    column: $table.lineEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredChunksTableAnnotationComposer
    extends Composer<_$StorageDatabase, $StoredChunksTable> {
  $$StoredChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lineStart =>
      $composableBuilder(column: $table.lineStart, builder: (column) => column);

  GeneratedColumn<int> get lineEnd =>
      $composableBuilder(column: $table.lineEnd, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  Expression<T> storedEmbeddingsRefs<T extends Object>(
    Expression<T> Function($$StoredEmbeddingsTableAnnotationComposer a) f,
  ) {
    final $$StoredEmbeddingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.storedEmbeddings,
      getReferencedColumn: (t) => t.chunkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredEmbeddingsTableAnnotationComposer(
            $db: $db,
            $table: $db.storedEmbeddings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StoredChunksTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $StoredChunksTable,
          StoredChunk,
          $$StoredChunksTableFilterComposer,
          $$StoredChunksTableOrderingComposer,
          $$StoredChunksTableAnnotationComposer,
          $$StoredChunksTableCreateCompanionBuilder,
          $$StoredChunksTableUpdateCompanionBuilder,
          (StoredChunk, $$StoredChunksTableReferences),
          StoredChunk,
          PrefetchHooks Function({bool storedEmbeddingsRefs})
        > {
  $$StoredChunksTableTableManager(
    _$StorageDatabase db,
    $StoredChunksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<int> lineStart = const Value.absent(),
                Value<int> lineEnd = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> metadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredChunksCompanion(
                id: id,
                ordinal: ordinal,
                sourcePath: sourcePath,
                lineStart: lineStart,
                lineEnd: lineEnd,
                content: content,
                type: type,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int ordinal,
                required String sourcePath,
                required int lineStart,
                required int lineEnd,
                required String content,
                required String type,
                required String metadataJson,
                Value<int> rowid = const Value.absent(),
              }) => StoredChunksCompanion.insert(
                id: id,
                ordinal: ordinal,
                sourcePath: sourcePath,
                lineStart: lineStart,
                lineEnd: lineEnd,
                content: content,
                type: type,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoredChunksTable, StoredChunk>(table),
                  $$StoredChunksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({storedEmbeddingsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (storedEmbeddingsRefs) db.storedEmbeddings,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (storedEmbeddingsRefs)
                    await $_getPrefetchedDataByColumns<
                      StoredChunk,
                      $StoredChunksTable,
                      StoredEmbedding,
                      $StoredEmbeddingsTable
                    >(
                      currentTable: table,
                      referencedTable: $$StoredChunksTableReferences
                          ._storedEmbeddingsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$StoredChunksTableReferences(
                            db,
                            table,
                            p0,
                          ).storedEmbeddingsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'chunk_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$StoredChunksTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $StoredChunksTable,
      StoredChunk,
      $$StoredChunksTableFilterComposer,
      $$StoredChunksTableOrderingComposer,
      $$StoredChunksTableAnnotationComposer,
      $$StoredChunksTableCreateCompanionBuilder,
      $$StoredChunksTableUpdateCompanionBuilder,
      (StoredChunk, $$StoredChunksTableReferences),
      StoredChunk,
      PrefetchHooks Function({bool storedEmbeddingsRefs})
    >;
typedef $$StoredEmbeddingsTableCreateCompanionBuilder =
    StoredEmbeddingsCompanion Function({
      required String chunkId,
      required String source,
      required String model,
      required int dimension,
      required Uint8List vector,
      Value<int> rowid,
    });
typedef $$StoredEmbeddingsTableUpdateCompanionBuilder =
    StoredEmbeddingsCompanion Function({
      Value<String> chunkId,
      Value<String> source,
      Value<String> model,
      Value<int> dimension,
      Value<Uint8List> vector,
      Value<int> rowid,
    });

final class $$StoredEmbeddingsTableReferences
    extends
        BaseReferences<
          _$StorageDatabase,
          $StoredEmbeddingsTable,
          StoredEmbedding
        > {
  $$StoredEmbeddingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $StoredChunksTable _chunkIdTable(_$StorageDatabase db) => db
      .storedChunks
      .createAlias('stored_embeddings__chunk_id__stored_chunks__id');

  $$StoredChunksTableProcessedTableManager get chunkId {
    final $_column = $_itemColumn<String>('chunk_id')!;

    final manager = $$StoredChunksTableTableManager(
      $_db,
      $_db.storedChunks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chunkIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StoredEmbeddingsTableFilterComposer
    extends Composer<_$StorageDatabase, $StoredEmbeddingsTable> {
  $$StoredEmbeddingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnFilters(column),
  );

  $$StoredChunksTableFilterComposer get chunkId {
    final $$StoredChunksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chunkId,
      referencedTable: $db.storedChunks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredChunksTableFilterComposer(
            $db: $db,
            $table: $db.storedChunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredEmbeddingsTableOrderingComposer
    extends Composer<_$StorageDatabase, $StoredEmbeddingsTable> {
  $$StoredEmbeddingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnOrderings(column),
  );

  $$StoredChunksTableOrderingComposer get chunkId {
    final $$StoredChunksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chunkId,
      referencedTable: $db.storedChunks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredChunksTableOrderingComposer(
            $db: $db,
            $table: $db.storedChunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredEmbeddingsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $StoredEmbeddingsTable> {
  $$StoredEmbeddingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get dimension =>
      $composableBuilder(column: $table.dimension, builder: (column) => column);

  GeneratedColumn<Uint8List> get vector =>
      $composableBuilder(column: $table.vector, builder: (column) => column);

  $$StoredChunksTableAnnotationComposer get chunkId {
    final $$StoredChunksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chunkId,
      referencedTable: $db.storedChunks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredChunksTableAnnotationComposer(
            $db: $db,
            $table: $db.storedChunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredEmbeddingsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $StoredEmbeddingsTable,
          StoredEmbedding,
          $$StoredEmbeddingsTableFilterComposer,
          $$StoredEmbeddingsTableOrderingComposer,
          $$StoredEmbeddingsTableAnnotationComposer,
          $$StoredEmbeddingsTableCreateCompanionBuilder,
          $$StoredEmbeddingsTableUpdateCompanionBuilder,
          (StoredEmbedding, $$StoredEmbeddingsTableReferences),
          StoredEmbedding,
          PrefetchHooks Function({bool chunkId})
        > {
  $$StoredEmbeddingsTableTableManager(
    _$StorageDatabase db,
    $StoredEmbeddingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredEmbeddingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredEmbeddingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredEmbeddingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> chunkId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> dimension = const Value.absent(),
                Value<Uint8List> vector = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredEmbeddingsCompanion(
                chunkId: chunkId,
                source: source,
                model: model,
                dimension: dimension,
                vector: vector,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String chunkId,
                required String source,
                required String model,
                required int dimension,
                required Uint8List vector,
                Value<int> rowid = const Value.absent(),
              }) => StoredEmbeddingsCompanion.insert(
                chunkId: chunkId,
                source: source,
                model: model,
                dimension: dimension,
                vector: vector,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoredEmbeddingsTable, StoredEmbedding>(table),
                  $$StoredEmbeddingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chunkId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chunkId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chunkId,
                                referencedTable:
                                    $$StoredEmbeddingsTableReferences
                                        ._chunkIdTable(db),
                                referencedColumn:
                                    $$StoredEmbeddingsTableReferences
                                        ._chunkIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StoredEmbeddingsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $StoredEmbeddingsTable,
      StoredEmbedding,
      $$StoredEmbeddingsTableFilterComposer,
      $$StoredEmbeddingsTableOrderingComposer,
      $$StoredEmbeddingsTableAnnotationComposer,
      $$StoredEmbeddingsTableCreateCompanionBuilder,
      $$StoredEmbeddingsTableUpdateCompanionBuilder,
      (StoredEmbedding, $$StoredEmbeddingsTableReferences),
      StoredEmbedding,
      PrefetchHooks Function({bool chunkId})
    >;
typedef $$GenerationRecordsTableCreateCompanionBuilder =
    GenerationRecordsCompanion Function({
      Value<int> id,
      required String recordJson,
      required String checksum,
    });
typedef $$GenerationRecordsTableUpdateCompanionBuilder =
    GenerationRecordsCompanion Function({
      Value<int> id,
      Value<String> recordJson,
      Value<String> checksum,
    });

class $$GenerationRecordsTableFilterComposer
    extends Composer<_$StorageDatabase, $GenerationRecordsTable> {
  $$GenerationRecordsTableFilterComposer({
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

  ColumnFilters<String> get recordJson => $composableBuilder(
    column: $table.recordJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GenerationRecordsTableOrderingComposer
    extends Composer<_$StorageDatabase, $GenerationRecordsTable> {
  $$GenerationRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get recordJson => $composableBuilder(
    column: $table.recordJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GenerationRecordsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $GenerationRecordsTable> {
  $$GenerationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordJson => $composableBuilder(
    column: $table.recordJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);
}

class $$GenerationRecordsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $GenerationRecordsTable,
          GenerationRecord,
          $$GenerationRecordsTableFilterComposer,
          $$GenerationRecordsTableOrderingComposer,
          $$GenerationRecordsTableAnnotationComposer,
          $$GenerationRecordsTableCreateCompanionBuilder,
          $$GenerationRecordsTableUpdateCompanionBuilder,
          (
            GenerationRecord,
            BaseReferences<
              _$StorageDatabase,
              $GenerationRecordsTable,
              GenerationRecord
            >,
          ),
          GenerationRecord,
          PrefetchHooks Function()
        > {
  $$GenerationRecordsTableTableManager(
    _$StorageDatabase db,
    $GenerationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GenerationRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GenerationRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GenerationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> recordJson = const Value.absent(),
                Value<String> checksum = const Value.absent(),
              }) => GenerationRecordsCompanion(
                id: id,
                recordJson: recordJson,
                checksum: checksum,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String recordJson,
                required String checksum,
              }) => GenerationRecordsCompanion.insert(
                id: id,
                recordJson: recordJson,
                checksum: checksum,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GenerationRecordsTable, GenerationRecord>(table),
                  BaseReferences<
                    _$StorageDatabase,
                    $GenerationRecordsTable,
                    GenerationRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GenerationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $GenerationRecordsTable,
      GenerationRecord,
      $$GenerationRecordsTableFilterComposer,
      $$GenerationRecordsTableOrderingComposer,
      $$GenerationRecordsTableAnnotationComposer,
      $$GenerationRecordsTableCreateCompanionBuilder,
      $$GenerationRecordsTableUpdateCompanionBuilder,
      (
        GenerationRecord,
        BaseReferences<
          _$StorageDatabase,
          $GenerationRecordsTable,
          GenerationRecord
        >,
      ),
      GenerationRecord,
      PrefetchHooks Function()
    >;

class $StorageDatabaseManager {
  final _$StorageDatabase _db;
  $StorageDatabaseManager(this._db);
  $$StoredChunksTableTableManager get storedChunks =>
      $$StoredChunksTableTableManager(_db, _db.storedChunks);
  $$StoredEmbeddingsTableTableManager get storedEmbeddings =>
      $$StoredEmbeddingsTableTableManager(_db, _db.storedEmbeddings);
  $$GenerationRecordsTableTableManager get generationRecords =>
      $$GenerationRecordsTableTableManager(_db, _db.generationRecords);
}
