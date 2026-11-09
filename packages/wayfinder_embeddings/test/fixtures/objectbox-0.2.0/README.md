# Historical ignored-namespace fixture

This synthetic ObjectBox store was written by Wayfinder 0.2.0 (commit
`53ecb10`) using Dart objectbox 5.0.4 and native 5.3.2 on macOS arm64.
It contains no user/client data. `knowledge_store_layout_test.dart` copies its
opaque files into a historical namespace and verifies that indexing, forget
and pruning never open, modify or delete that namespace.

The ObjectBox runtime, generated bindings and fixture-generation program were
removed with the optional backend in embeddings 0.6.0-beta.1. These bytes are
retained only as historical compatibility-test input; no current code opens
them as a database. Do not regenerate or normalize them.
