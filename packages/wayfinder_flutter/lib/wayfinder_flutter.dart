/// Flutter models and widgets for reading OKF knowledge bundles.
///
/// - [KnowledgeProject] is what a reader asks of a project's knowledge, and
///   the models it answers with.
/// - [KnowledgeGraphCanvas] draws a laid-out [KnowledgeGraphScene].
/// - [WayfinderReaderTheme] gives the widgets their colours and type, so a host
///   can map its own design system onto them.
///
/// Hosts own sign-in, storage, navigation and app chrome. Widgets report intent
/// through callbacks.
library;

export 'src/graph/knowledge_graph_canvas.dart';
export 'src/graph/knowledge_graph_labels.dart';
export 'src/graph/knowledge_type_palette.dart';
export 'src/model/knowledge.dart';
export 'src/model/knowledge_file_tree_projection.dart';
export 'src/model/knowledge_files.dart';
export 'src/model/knowledge_links.dart';
export 'src/theme/wayfinder_reader_theme.dart';
