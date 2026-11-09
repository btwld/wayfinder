import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:wayfinder/knowledge.dart';

import '../controller/knowledge_reader_controller.dart';
import '../graph/knowledge_graph_canvas.dart';
import '../graph/knowledge_type_palette.dart';
import '../theme/wayfinder_reader_theme.dart';

/// Minimal shared browsing presentation. Host owns project selection, grants,
/// controller lifetime and app chrome. Content is verbatim text, not fabricated
/// rendering. No network link or attachment is opened implicitly.
final class KnowledgeReader extends StatefulWidget {
  const KnowledgeReader({super.key, required this.controller});
  final KnowledgeReaderController controller;
  @override
  State<KnowledgeReader> createState() => _KnowledgeReaderState();
}

enum _View { read, source, graph, validation }

final class _KnowledgeReaderState extends State<KnowledgeReader> {
  _View view = _View.read;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final snapshot = c.snapshot;
      final bundle = c.bundle;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              if (snapshot != null)
                DropdownButton<String>(
                  key: const Key('reader-bundles'),
                  value: bundle?.id,
                  hint: const Text('Bundle'),
                  items: [
                    for (final b in snapshot.bundles)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(b.summary.path),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      c.selectBundle(id);
                      if (view == _View.graph) {
                        c.showGraph();
                      }
                    }
                  },
                ),
              TextButton(
                onPressed: c.refreshing
                    ? null
                    : () async {
                        await c.refresh();
                        if (mounted &&
                            identical(c, widget.controller) &&
                            view == _View.graph &&
                            !c.refreshing &&
                            c.error == null &&
                            c.snapshot != null) {
                          await c.showGraph();
                        }
                      },
                child: const Text('Refresh'),
              ),
              Text(c.searchUnavailableReason),
            ],
          ),
          if (c.refreshing || c.loading) const LinearProgressIndicator(),
          if (c.error != null)
            Text(c.error.toString(), key: const Key('reader-error')),
          Wrap(
            spacing: 8,
            children: [
              for (final option in _View.values)
                ChoiceChip(
                  label: Text(switch (option) {
                    _View.read => 'Read',
                    _View.source => 'Source',
                    _View.graph => 'Graph',
                    _View.validation => 'Validation',
                  }),
                  selected: view == option,
                  onSelected: (_) {
                    setState(() => view = option);
                    if (option == _View.graph) {
                      c.showGraph();
                    }
                  },
                ),
            ],
          ),
          Expanded(
            child: snapshot == null
                ? const Center(child: Text('Refresh to open knowledge.'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final files = [
                        ...?(bundle?.files),
                        ...snapshot.files.where((f) => f.handle.bundle == null),
                      ];
                      final content = _content(c, bundle);
                      if (constraints.maxWidth < 700) {
                        return Column(
                          children: [
                            DropdownButton<KnowledgeResourceEntry>(
                              key: const Key('reader-files'),
                              isExpanded: true,
                              value: files.contains(c.selectedFile)
                                  ? c.selectedFile
                                  : null,
                              hint: const Text('Select a file'),
                              items: [
                                for (final f in files)
                                  DropdownMenuItem(
                                    value: f,
                                    child: Text(_fileLabel(f, snapshot)),
                                  ),
                              ],
                              onChanged: (file) {
                                if (file != null) {
                                  setState(() => view = _View.read);
                                  c.openFile(file);
                                }
                              },
                            ),
                            Expanded(child: content),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(
                            width: 240,
                            child: ListView(
                              children: [
                                for (final file in files)
                                  ListTile(
                                    key: ValueKey(file.handle),
                                    selected: identical(file, c.selectedFile),
                                    title: Text(_fileLabel(file, snapshot)),
                                    onTap: () {
                                      setState(() => view = _View.read);
                                      c.openFile(file);
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: content),
                        ],
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );

  String _fileLabel(
    KnowledgeResourceEntry file,
    KnowledgeProjectSnapshot snapshot,
  ) {
    final bundleId = file.handle.bundle;
    return bundleId == null
        ? 'Project: ${file.handle.path}'
        : '${snapshot.bundle(bundleId).summary.path}/${file.handle.path}';
  }

  Widget _content(
    KnowledgeReaderController c,
    KnowledgeBundleSnapshot? bundle,
  ) {
    if (view == _View.validation) {
      return _text(
        'Validation unavailable (not assessed).\n${bundle?.validation.reason ?? 'Select a bundle.'}',
        key: const Key('reader-validation'),
      );
    }
    if (view == _View.graph) {
      final scene = c.scene;
      if (scene == null) {
        return const Center(child: Text('Graph unavailable or loading.'));
      }
      return WayfinderReaderTheme(
        data: Theme.of(context).brightness == Brightness.dark
            ? const WayfinderReaderThemeData.dark()
            : const WayfinderReaderThemeData.light(),
        child: KnowledgeGraphCanvas(
          scene: scene,
          palette: KnowledgeTypePalette.of(bundle!.concepts),
          activeId: c.selectedGraphNodeId,
          attentionOf: (_) => null,
          onSelect: c.selectGraphNode,
          onOpen: (id) {
            if (!scene.nodes.any((node) => node.id == id && node.isConcept)) {
              return;
            }
            setState(() => view = _View.read);
            c.openConcept(id);
          },
        ),
      );
    }
    final source = c.source;
    if (source == null) return const Center(child: Text('Select a file.'));
    if (view == _View.read && c.concept != null) {
      final concept = c.concept!;
      return _text(
        '${concept.title}\n\n${concept.body}',
        key: const Key('reader-concept'),
      );
    }
    // Known binary media and unknown invalid UTF-8 stay binary. The bounded hex
    // preview is exact bytes, not invented replacement characters or rendering.
    String? text;
    final media = source.entry.mediaType;
    if (media == null ||
        media.startsWith('text/') ||
        media == 'application/json') {
      try {
        text = utf8.decode(source.bytes);
      } on FormatException {
        /* binary */
      }
    }
    if (text != null && !text.contains('\u0000')) {
      return _text(text, key: const Key('reader-source'));
    }
    final hex = source.bytes
        .take(256)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return _text(
      'Binary attachment · ${source.bytes.length} bytes\n'
      'SHA-256 ${source.entry.digest}\n\n$hex'
      '${source.bytes.length > 256 ? '\n(first 256 bytes)' : ''}',
      key: const Key('reader-binary'),
    );
  }

  Widget _text(String text, {Key? key}) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Align(
      alignment: Alignment.topLeft,
      child: SelectableText(text, key: key),
    ),
  );
}
