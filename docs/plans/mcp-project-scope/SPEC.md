---
kind: plan
date: 2026-09-30
repository: btwld/wayfinder
branch: feat/flutter-knowledge-bundle-implementation
commit: 0d7a4b8543f775059546442fe99b5958e5f33794
worktree: /Users/leofarias/Documents/Codex/2026-09-29/ca/work/wayfinder-flutter
skill: engineering-kit:writing-plans
session: null
status: draft
---

# Root-scoped local MCP

## Decision

Wayfinder MCP starts without a bundle or project argument:

~~~sh
wayfinder mcp
~~~

The server remains lightweight at startup. It does not load a bundle, open an
embedding model, validate, or index.

Each tool call accepts an optional root path. The user-facing field is root; the
internal name may be scopeRoot.

~~~json
{
  "root": "/path/to/flutterapp",
  "query": "navigation"
}
~~~

If root is omitted, the server uses its process working directory. A resolved
root containing wayfinder.json is treated as a configured workspace and its
bundles are discovered for the operation. A resolved root that is itself a
valid standalone bundle remains supported.

An optional bundle field narrows a project operation to one registered bundle.
The normal default searches all configured bundles.

## Tool behavior

- validate resolves the root and validates its configured bundle set.
- index resolves the root and indexes its configured bundle set.
- search resolves the root, discovers bundles, applies optional bundle and
  metadata filters, and searches the selected set.
- graph resolves the root and projects its configured graph scope.

No tool implicitly indexes or silently repairs a stale index. Search retains the
existing explicit index requirement.

## Compatibility

Continue accepting a direct bundle path during migration when the path is
clearly an OKF bundle. This is a compatibility mode, not the default project
model. Existing callers using wayfinder mcp <bundle> must continue to work.

Update setup-generated MCP configuration to launch wayfinder mcp without a fixed
bundle path when the host supplies the workspace working directory. Hosts with
an uncertain working directory may pass an explicit root path in tool input.

## Implementation sequence

### 1. Add project resolution

Extend the MCP server with a resolver that accepts root, defaults to the process
working directory, detects wayfinder.json, and discovers configured bundles
using the same discovery code as the CLI. If no configuration exists, detect a
standalone bundle or return a clear scope error.

### 2. Extend the MCP input contracts

Add optional root and bundle fields to validate, index, search, and graph
inputs. Preserve existing query and limit validation. Add the metadata filter
object from the metadata-filtered search specification to search.

### 3. Remove startup bundle ownership

Change the MCP server lifecycle so it stores no startup-selected bundle. Resolve
the operation scope inside each tool call and retain existing resource cleanup,
stale-index checks, and read-only annotations.

### 4. Update setup and documentation

Update wayfinder setup, MCP README material, install guidance, and examples to
describe project-root resolution and the process-working-directory default.
Keep the direct bundle compatibility form documented as a migration path.

### 5. Test isolation and compatibility

Cover:

- no-argument MCP startup performs no indexing or model load;
- omitted root uses the process working directory;
- explicit roots resolve wayfinder.json;
- multiple configured roots can be searched through one server;
- bundle filters narrow the selected root;
- direct bundle startup remains compatible;
- stale indexes fail without implicit indexing;
- CLI and MCP project discovery select the same bundles;
- invalid or missing root paths return clear tool errors;
- resources close after each operation.

## Acceptance criteria

- One local MCP process can serve multiple Wayfinder roots.
- MCP does not initialize a root or bundle at startup.
- wayfinder.json is the source of bundle discovery when present.
- Search, index, validate, and graph share the same root resolution.
- Existing direct-bundle callers continue to work during migration.
- Setup no longer hardcodes flutter-dev-kit or another single bundle.
