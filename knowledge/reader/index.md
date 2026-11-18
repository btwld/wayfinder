# Architecture Decision Record

* [Bound document capture and inventory the rest](bound-document-capture.md) - Only classified Markdown and configuration bytes are captured, and attachments and over-budget documents are inventoried with refusals.
* [Browse read-only through core entry points](browse-read-only-through-core-entry-points.md) - Portable values behind `knowledge.dart`, bounded native browsing behind `project.dart`, and the rules for roots, hidden entries and capture reuse.
* [Keep the Flutter reader outside the Dart workspace](keep-the-flutter-reader-outside-the-workspace.md) - Reader models and widgets live in `packages/wayfinder_flutter`, free of any design kit and out of the pub workspace.
