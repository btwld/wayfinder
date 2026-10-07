# The Profile questions

Every Profile settles its identity and answers the enforcement question. The
numbered questions are an optional checklist. The author ratifies each
answer. "The Profile says nothing here" is a valid answer to any checklist
question, and OKF then governs.

Each question says what a good answer contains and where the answer lands.
"Package" means `wayfinder-profile.json`. "Skill" means a section of the
Profile's skill. "Review map" means a check in the skill's review map.

## Identity

Settle these before the enforcement question:

- **Id.** Lowercase kebab-case, at most 64 characters, not a reserved name.
  It becomes the finding namespace, the `wayfinder.json` key, and the skill
  name, so choose one that can last.
- **Release scheme.** How releases are named, and how a breaking change shows.
- **OKF release.** The one the Profile binds to (`implements`).
- **Parent.** Whether it builds on another Profile (`extends`), and at which
  revision.
- **Home.** The repository and path of the package, and the `docs` URL.

## What must a machine enforce, and what is judgment?

Ask this first. A good answer lists each requirement a machine should
check, in the author's words, with whether a violation fails the gate or
only asks for action. It lists separately the decisions that need a
person's context. Each enforced requirement becomes a rule, and each
decision becomes skill guidance with a review-map check. A Profile with
rules and no judgment needs no skill. Lands in: package rules; skill and
review map.

## Optional checklist

These questions cover what Profiles often decide. Offer them in any order,
and record "says nothing" for each one the author skips.

### 1. What earns a concept, and what never does?

A good answer states the test that separates durable knowledge from
activity, in the author's words, and names kinds of events or artifacts that
never become concepts on their own. Lands in: skill, review map.

### 2. When does an outcome get its own concept, and when does it stay embedded?

A good answer gives the deciding test, such as whether the outcome has its
own lifecycle, and the default for an ambiguous case. Lands in: skill,
review map.

### 3. When is a concept split?

A good answer names the signal that calls for a split and the signals that
do not, such as size alone. Lands in: skill, review map.

### 4. Are records of interactions concepts?

A good answer says when a meeting, call, or thread earns a record, what the
record holds, and what happens to a single outcome that mattered. Lands in:
skill, review map. A fixed home for such records is question 8.

### 5. Which types does the Profile declare, and how does an author choose between them?

A good answer lists each type with one sentence of intended content, says
whether a project may add types, and gives a test for each pair of types
authors confuse. Lands in: package `types` and a rule that used types are
declared; skill and review map for choosing.

### 6. What body shape does each type start from?

A good answer gives starting headings per type and says whether they are
prompts or requirements. Lands in: skill for prompts; a rule over `headings`
only when a heading is required.

### 7. How are directories named, and when is one earned?

A good answer says what a directory name stands for, which names are
forbidden, whether a directory needs a minimum corpus, and whether overview
pages are allowed. Lands in: skill, review map; a rule over `directory` or
`file` paths for any name that is always wrong.

### 8. Where does a concept live, and what must each directory hold?

A good answer gives the placement test, each fixed directory with its
membership, and the files the bundle root and each directory must hold, such
as a log or a generated index. Lands in: skill, review map; a rule over
`concept` or `file` paths for membership a machine can check; a builtin rule
for required or generated files.

### 9. Which relationship names does the Profile declare, and how does an author choose one?

A good answer lists each name with its meaning, read from the concept
outward, and says how to choose between close names and what never to
write. Lands in: package `relationships`, plus `frontmatter_keys` for the
`relationships` key and rules for its shape and declared names; skill and
review map for choosing.

### 10. What stays outside the bundle?

A good answer names the records another system owns, such as tracker issues
or pull requests, and how a concept links to them instead of copying them.
Lands in: skill, review map.

### 11. What is the provenance and trust stance?

A good answer says when `sources` is required, when `generated` and
`verified` are written and never written, how actors are described, and when
`stale_after` is allowed. Lands in: skill, review map; rules or advisories
for shapes a machine can check, such as timestamp formats.

### 12. Which OKF metadata does the Profile narrow?

A good answer lists each narrowing: required fields, allowed `status`
values, what `tags` may mean, and whether frontmatter keys beyond OKF's are
allowed. Lands in: rules for the mechanical part; package `frontmatter_keys`
for each added key; skill for meaning a machine cannot check.

### 13. How do identity and lifecycle work?

A good answer covers slugs, dates in paths, identifiers cited elsewhere,
when a path may move and when it freezes, deprecation versus deletion, and
which events the log records. Lands in: skill, review map; rules for a
mechanical log or path convention.

### 14. How is external material mirrored into the bundle?

A good answer says when material may be mirrored, where it goes, the policy
per medium, and how originals are kept. Lands in: skill, review map; rules
over `file` paths for placement.

### 15. Is there a raw-evidence layer outside the bundle?

A good answer says whether one exists, its layout, its intake record, and
how concepts cite it. Lands in: skill, with templates.

### 16. What does review judge, and when does a reviewer escalate?

A good answer turns every judgment answer into a review-map check with
an id, a force, and a link to its guidance. It lists what is permitted so a
reviewer never flags it, and the cases a reviewer escalates as
`NEEDS HUMAN`. Lands in: skill review map.

### 17. How does a project adopt the Profile?

A good answer gives the `wayfinder.json` entry, the root-file templates, the
first log entry, and the lines the project's agent instructions need. Lands
in: skill adoption reference.
