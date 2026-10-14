# wayfinder

Core Dart library that validates an OKF bundle with okf, then evaluates the
rules of the Profile package a project selects. It embeds no Profile.
`ProfilePackage` parses a package, and `ProfileValidator` returns a
`ProfileValidationResult` with the OKF report, Profile findings, engine
diagnostics (`EngineDiagnostic`), and the gate derived from them
(`GateState`).

```dart
import 'package:wayfinder/wayfinder.dart';
```

This package replaces `okf_profile`. Change the dependency to `wayfinder: ^0.0.1`
and imports from `package:okf_profile/okf_profile.dart` to
`package:wayfinder/wayfinder.dart`. Previously published `okf_profile` versions
remain available for existing consumers.

For the command and MCP server, install **wayfinder_cli**:

```sh
dart pub global activate wayfinder_cli
wayfinder validate knowledge
wayfinder mcp knowledge
```

For indexing and search without native setup, use the complete scripted
installation in the [installation guide](../../docs/install.md).
The reusable retrieval library is `wayfinder_embeddings`.

Before 0.0.1, the published `wayfinder` prereleases were the application package.
CLI users migrating from those prereleases must deactivate the old package and
activate `wayfinder_cli`; `wayfinder` is now a library with no executable.
