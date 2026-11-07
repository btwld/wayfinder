import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const root = String.fromEnvironment('WAYFINDER_PROJECT');
  final KnowledgeProject project = root.isEmpty
      ? MemoryKnowledgeProject(id: 'example:memory', capture: _fixture())
      : await LocalKnowledgeProject.open(
          root: Directory(root),
          id: 'example:local',
        );
  final controller = KnowledgeReaderController(project: project);
  await controller.refresh();
  runApp(_Example(project: project, controller: controller));
}

final class _Example extends StatefulWidget {
  const _Example({required this.project, required this.controller});
  final KnowledgeProject project;
  final KnowledgeReaderController controller;
  @override
  State<_Example> createState() => _ExampleState();
}

final class _ExampleState extends State<_Example> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Model-free knowledge reader')),
      body: KnowledgeReader(controller: widget.controller),
    ),
  );
  @override
  void dispose() {
    // The host owns both; the controller never closes its borrowed project.
    widget.controller.close().whenComplete(widget.project.close);
    widget.controller.dispose();
    super.dispose();
  }
}

KnowledgeCapture _fixture() => KnowledgeCapture(
  files: [
    KnowledgeCapturedFile(
      bundle: 'example:docs',
      path: 'welcome.md',
      mediaType: 'text/markdown',
      bytes: utf8.encode('# Welcome\nThis reader needs no embedding model.'),
    ),
    KnowledgeCapturedFile(
      bundle: 'example:docs',
      path: 'attachment.bin',
      bytes: [0, 255, 128],
    ),
  ],
  bundles: [
    KnowledgeCapturedBundle(
      id: 'example:docs',
      summary: const KnowledgeBundleSummary(
        name: 'knowledge',
        path: 'knowledge',
        conceptCount: 1,
      ),
      concepts: const [
        KnowledgeConcept(
          bundle: 'example:docs',
          id: 'welcome',
          path: 'knowledge/welcome.md',
          citation: 'knowledge/welcome.md:1-2',
          title: 'Welcome',
          type: 'Guide',
          status: 'draft',
          trust: KnowledgeTrust.unverified,
          frontmatter: {},
          body: 'This reader needs no embedding model.',
          lineCount: 2,
        ),
      ],
      graph: const KnowledgeGraph(
        bundle: 'example:docs',
        nodes: [
          KnowledgeGraphNode(
            id: 'welcome',
            path: 'knowledge/welcome.md',
            title: 'Welcome',
            type: 'Guide',
          ),
        ],
        edges: [],
      ),
    ),
  ],
);
