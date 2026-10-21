/// DartChunker — AST-driven chunker for Dart source files.
/// -------------------------------------------------------
/// Features:
/// - Produces semantically meaningful chunks (class/mixin/extension/enum/etc.)
/// - Includes documentation comments and annotations in summaries
/// - Summarizes both containers and large functions/methods/constructors
/// - Optional "directives" chunk (library/import/export/part)
/// - Stable line ranges, helpful metadata, and reduced duplication
///
/// Recommended usage:
/// - Run this in an ingestion step (desktop/CLI/CI), persist chunks + embeddings
/// - Ship only the vector DB to your app; avoid bundling the Analyzer in mobile
///
/// Requires:
///   analyzer: ^6.x (dev_dependency)
///
/// Example:
///   final chunker = DartChunker(maxChunkLength: 1600);
///   final chunks = chunker.chunkContent(content, ChunkMetadata(...));
///
/// Notes:
/// - line numbers are 1-based
/// - `summary=true` & `truncated=true` metadata when body is omitted
/// - Set `alwaysSummarizeContainers=false` if you want full container bodies too
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../../models/chunk.dart';
import '../../models/chunk_metadata.dart';
import '../../util/checks.dart';
import '../base_chunker.dart';
import '../chunk_budget.dart';

typedef _AddNode =
    void Function(
      AstNode node,
      String type, {
      Map<String, Object?> metadataOverrides,
      bool isContainer,
    });

class DartChunker extends BaseChunker {
  DartChunker({
    int maxChunkLength = 1600, // good default for ~2k-token embedders
    this.alwaysSummarizeContainers =
        true, // avoid duplicating body with members
    this.emitDirectivesChunk = true, // include library/import/export/part
    this.includeDocAndAnnotations = true, // include /// docs & @annotations
  }) : maxChunkLength = checkPositive(maxChunkLength, 'maxChunkLength');

  /// Upper bound for chunk text length, measured in non-whitespace characters.
  final int maxChunkLength;

  /// If true, containers (class/mixin/extension/(type)/enum) are *always*
  /// summarized to doc+signature, never full bodies (prevents duplication).
  final bool alwaysSummarizeContainers;

  /// If true, emits a "directives" chunk spanning library/import/export/part.
  final bool emitDirectivesChunk;

  /// If true, summaries start at doc comment or first annotation (when present).
  final bool includeDocAndAnnotations;

  @override
  String get contentType => 'dart';

  @override
  Set<String> get supportedExtensions => const {'dart', '.dart'};

  @override
  List<Chunk> chunkContent(String content, ChunkMetadata metadata) {
    final parseResult = parseString(
      content: content,
      throwIfDiagnostics: false,
    );
    final unit = parseResult.unit;
    final lineInfo = parseResult.lineInfo;
    final chunks = <Chunk>[];

    // ----------------- helpers -----------------

    int lineForOffset(int offset) => lineInfo
        .getLocation(offset.clamp(0, content.isEmpty ? 0 : content.length - 1))
        .lineNumber;

    /// For nodes, `end` is exclusive; compute a stable inclusive end line.
    int safeEndLine(AstNode node) =>
        lineForOffset((node.end > node.offset) ? node.end - 1 : node.offset);

    /// Prefer doc comment start or first annotation start, else node.offset.
    int declStartOffset(AstNode node) {
      if (!includeDocAndAnnotations) return node.offset;
      if (node is AnnotatedNode) {
        final doc = node.documentationComment;
        if (doc != null) return doc.offset;
        if (node.metadata.isNotEmpty) return node.metadata.first.offset;
      }
      return node.offset;
    }

    int? fnBodyBoundary(FunctionBody b) => switch (b) {
      BlockFunctionBody() => b.block.leftBracket.offset,
      ExpressionFunctionBody() => b.functionDefinition.offset, // '=>'
      EmptyFunctionBody() => b.semicolon.offset,
      _ => null,
    };

    /// Where the "body" begins:
    /// - containers: '{'
    /// - methods/functions: '{' or '=>', or ';' (empty)
    /// - ctors: '{' or ';'
    /// Returns null if not applicable.
    int? bodyBoundaryOffset(AstNode node) => switch (node) {
      ClassDeclaration() => node.leftBracket.offset,
      MixinDeclaration() => node.leftBracket.offset,
      ExtensionDeclaration() => node.leftBracket.offset,
      ExtensionTypeDeclaration() => node.leftBracket.offset,
      EnumDeclaration() => node.leftBracket.offset,
      MethodDeclaration() => fnBodyBoundary(node.body),
      ConstructorDeclaration() => fnBodyBoundary(node.body),
      FunctionDeclaration() => fnBodyBoundary(node.functionExpression.body),
      _ => null,
    };

    void addNode(
      AstNode node,
      String type, {
      Map<String, Object?> metadataOverrides = const {},
      bool isContainer = false,
    }) {
      final start = declStartOffset(node);
      final endExclusive = node.end;
      String chunkText = content.substring(start, endExclusive);

      final md = <String, Object?>{...metadataOverrides};

      var chunkEndLine = safeEndLine(node);

      final bodyStart = bodyBoundaryOffset(node);
      final needsSummary =
          (isContainer && alwaysSummarizeContainers) ||
          (bodyStart != null &&
              !fitsNonWhitespaceBudget(chunkText, maxChunkLength));

      if (bodyStart != null && needsSummary) {
        // Stop BEFORE '{' or '=>' or ';' (do not include it)
        final summary = content.substring(start, bodyStart).trimRight();
        if (summary.isNotEmpty) {
          chunkText = summary;
          // Use the line of the last character before bodyStart, not bodyStart itself
          chunkEndLine = lineForOffset(
            bodyStart > start ? bodyStart - 1 : start,
          );
          md['summary'] = true;
          md['truncated'] = true;
        }
      }

      chunks.add(
        Chunk(
          sourcePath: metadata.sourcePath,
          lineStart: lineForOffset(start),
          lineEnd: chunkEndLine,
          content: chunkText,
          type: type,
          metadata: md,
        ),
      );
    }

    // --------------- directives chunk ---------------
    if (emitDirectivesChunk && unit.directives.isNotEmpty) {
      final first = unit.directives.first;
      final last = unit.directives.last;
      final dStart = includeDocAndAnnotations
          ? (first.documentationComment?.offset ??
                (first.metadata.isNotEmpty
                    ? first.metadata.first.offset
                    : first.offset))
          : first.offset;
      final dEnd = last.end;
      chunks.add(
        Chunk(
          sourcePath: metadata.sourcePath,
          lineStart: lineForOffset(dStart),
          lineEnd: lineForOffset(dEnd - 1),
          content: content.substring(dStart, dEnd).trimRight(),
          type: 'directives',
          metadata: {'count': unit.directives.length},
        ),
      );
    }

    // --------------- declarations ---------------
    for (final declaration in unit.declarations) {
      switch (declaration) {
        case ClassDeclaration():
          _handleClassDeclaration(declaration, addNode);
        case MixinDeclaration():
          _handleMixinDeclaration(declaration, addNode);
        case ExtensionDeclaration():
          _handleExtensionDeclaration(declaration, addNode);
        case ExtensionTypeDeclaration():
          _handleExtensionTypeDeclaration(declaration, addNode);
        case EnumDeclaration():
          _handleEnumDeclaration(declaration, addNode);
        case FunctionDeclaration():
          _handleFunctionDeclaration(declaration, addNode);
        case TopLevelVariableDeclaration():
          _handleTopLevelVariableDeclaration(declaration, addNode);
        case TypeAlias():
          addNode(
            declaration,
            'typeAlias',
            metadataOverrides: {
              'name': declaration.name.lexeme,
              if (declaration is GenericTypeAlias)
                'typeParams': ?declaration.typeParameters?.toSource(),
              // intentionally avoiding aliasedType to reduce API fragility
            },
          );
      }
    }

    // Fallback: if nothing parsed or file empty/broken, index whole file.
    if (chunks.isEmpty) {
      chunks.add(
        Chunk(
          sourcePath: metadata.sourcePath,
          lineStart: 1,
          lineEnd: lineInfo.lineCount,
          content: content,
          type: 'file',
        ),
      );
    }

    chunks.sort((a, b) => a.lineStart.compareTo(b.lineStart));
    return chunks;
  }

  void _addMethod(
    MethodDeclaration member,
    Map<String, Object?> scope,
    _AddNode addNode, {
    bool includeStaticAndTypeParams = true,
  }) {
    final kind = member.isGetter
        ? 'getter'
        : member.isSetter
        ? 'setter'
        : 'method';
    final name = member.operatorKeyword != null
        ? 'operator ${member.name.lexeme}'
        : member.name.lexeme;
    addNode(
      member,
      kind,
      metadataOverrides: {
        ...scope,
        'name': name,
        if (includeStaticAndTypeParams) 'static': member.isStatic,
        if (includeStaticAndTypeParams)
          'typeParams': ?member.typeParameters?.toSource(),
        'returnType': ?member.returnType?.toSource(),
        'params': ?member.parameters?.toSource(),
        'external': member.externalKeyword != null,
        'abstract': member.body is EmptyFunctionBody,
      },
    );
  }

  void _addField(
    FieldDeclaration member,
    Map<String, Object?> scope,
    _AddNode addNode,
  ) {
    addNode(
      member,
      'field',
      metadataOverrides: {
        ...scope,
        'static': member.isStatic,
        'external': member.externalKeyword != null,
        'late': member.fields.lateKeyword != null,
        'final': member.fields.keyword?.lexeme == 'final',
        'const': member.fields.keyword?.lexeme == 'const',
        'names': [for (final v in member.fields.variables) v.name.lexeme],
        'type': ?member.fields.type?.toSource(),
      },
    );
  }

  void _handleClassDeclaration(ClassDeclaration declaration, _AddNode addNode) {
    final className = declaration.name.lexeme;
    addNode(
      declaration,
      'class',
      metadataOverrides: {
        'name': className,
        'abstract': declaration.abstractKeyword != null,
        'typeParams': ?declaration.typeParameters?.toSource(),
        'extends': ?declaration.extendsClause?.superclass.toSource(),
        if (declaration.withClause != null)
          'with': [
            for (final t in declaration.withClause!.mixinTypes) t.toSource(),
          ],
        if (declaration.implementsClause != null)
          'implements': [
            for (final t in declaration.implementsClause!.interfaces)
              t.toSource(),
          ],
      },
      isContainer: true,
    );

    final scope = <String, Object?>{'class': className};
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        _addMethod(member, scope, addNode);
      } else if (member is ConstructorDeclaration) {
        addNode(
          member,
          'constructor',
          metadataOverrides: {
            'class': className,
            'name': member.name?.lexeme,
            'factory': member.factoryKeyword != null,
            'params': member.parameters.toSource(),
            if (member.initializers.isNotEmpty)
              'initializers': [
                for (final i in member.initializers) i.toSource(),
              ],
            'external': member.externalKeyword != null,
            'const': member.constKeyword != null,
          },
        );
      } else if (member is FieldDeclaration) {
        _addField(member, scope, addNode);
      }
    }
  }

  void _handleMixinDeclaration(MixinDeclaration declaration, _AddNode addNode) {
    final mixinName = declaration.name.lexeme;
    addNode(
      declaration,
      'mixin',
      metadataOverrides: {
        'name': mixinName,
        'typeParams': ?declaration.typeParameters?.toSource(),
        if (declaration.onClause != null)
          'on': [
            for (final t in declaration.onClause!.superclassConstraints)
              t.toSource(),
          ],
        if (declaration.implementsClause != null)
          'implements': [
            for (final t in declaration.implementsClause!.interfaces)
              t.toSource(),
          ],
      },
      isContainer: true,
    );

    final scope = <String, Object?>{'mixin': mixinName};
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        _addMethod(member, scope, addNode);
      } else if (member is FieldDeclaration) {
        _addField(member, scope, addNode);
      }
    }
  }

  void _handleExtensionDeclaration(
    ExtensionDeclaration declaration,
    _AddNode addNode,
  ) {
    final extensionName = declaration.name?.lexeme;
    final onClause = declaration.onClause?.extendedType.toSource();
    addNode(
      declaration,
      'extension',
      metadataOverrides: {
        'name': ?extensionName,
        'on': ?onClause,
        'typeParams': ?declaration.typeParameters?.toSource(),
      },
      isContainer: true,
    );

    final scope = <String, Object?>{
      'extension': ?extensionName,
      'on': onClause,
    };
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        _addMethod(member, scope, addNode);
      } else if (member is FieldDeclaration) {
        _addField(member, scope, addNode);
      }
    }
  }

  void _handleExtensionTypeDeclaration(
    ExtensionTypeDeclaration declaration,
    _AddNode addNode,
  ) {
    final name = declaration.name.lexeme;
    addNode(
      declaration,
      'extensionType',
      metadataOverrides: {
        'name': name,
        'typeParams': ?declaration.typeParameters?.toSource(),
        'on': declaration.representation.fieldType.toSource(),
        if (declaration.implementsClause != null)
          'implements': [
            for (final t in declaration.implementsClause!.interfaces)
              t.toSource(),
          ],
      },
      isContainer: true,
    );

    final scope = <String, Object?>{'extensionType': name};
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        _addMethod(member, scope, addNode);
      } else if (member is FieldDeclaration) {
        _addField(member, scope, addNode);
      }
    }
  }

  void _handleEnumDeclaration(EnumDeclaration declaration, _AddNode addNode) {
    final enumName = declaration.name.lexeme;
    addNode(
      declaration,
      'enum',
      metadataOverrides: {
        'name': enumName,
        'typeParams': ?declaration.typeParameters?.toSource(),
        if (declaration.withClause != null)
          'with': [
            for (final t in declaration.withClause!.mixinTypes) t.toSource(),
          ],
        if (declaration.implementsClause != null)
          'implements': [
            for (final t in declaration.implementsClause!.interfaces)
              t.toSource(),
          ],
      },
      isContainer: true,
    );

    final scope = <String, Object?>{'enum': enumName};
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        _addMethod(member, scope, addNode, includeStaticAndTypeParams: false);
      } else if (member is ConstructorDeclaration) {
        addNode(
          member,
          'constructor',
          metadataOverrides: {
            'enum': enumName,
            'name': member.name?.lexeme,
            'factory': member.factoryKeyword != null,
            'params': member.parameters.toSource(),
          },
        );
      }
    }
  }

  void _handleFunctionDeclaration(
    FunctionDeclaration declaration,
    _AddNode addNode,
  ) {
    final kind = declaration.isGetter
        ? 'getter'
        : declaration.isSetter
        ? 'setter'
        : 'function';
    addNode(
      declaration,
      kind,
      metadataOverrides: {
        'name': declaration.name.lexeme,
        'returnType': ?declaration.returnType?.toSource(),
        'params': ?declaration.functionExpression.parameters?.toSource(),
        'typeParams': ?declaration.functionExpression.typeParameters
            ?.toSource(),
        'external': declaration.externalKeyword != null,
      },
    );
  }

  void _handleTopLevelVariableDeclaration(
    TopLevelVariableDeclaration declaration,
    _AddNode addNode,
  ) {
    addNode(
      declaration,
      'topLevelVariable',
      metadataOverrides: {
        'names': [
          for (final e in declaration.variables.variables) e.name.lexeme,
        ],
        'type': ?declaration.variables.type?.toSource(),
        'late': declaration.variables.lateKeyword != null,
        'final': declaration.variables.keyword?.lexeme == 'final',
        'const': declaration.variables.keyword?.lexeme == 'const',
        'external': declaration.externalKeyword != null,
      },
    );
  }
}
