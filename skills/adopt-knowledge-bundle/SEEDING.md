# Seeding a Bitwild Profile 2026.3 bundle

The default adoption seed has one project configuration file and two bundle
root files. Replace placeholders with project facts. Do not create subject
areas until the actual corpus warrants them. The old 2026.2 literal templates
remain in [SEEDING-2026.2.md](./SEEDING-2026.2.md) for legacy dispatch; do not
mix their `profile.md`, `types.md`, or `actors.md` into a new bundle.

## `wayfinder.json` (project root)

```json
{
  "version": 1,
  "profiles": {
    "bitwild_profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "main",
        "path": "profile"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

Add custom `types`, `tags`, and `actors` to this entry only as needed. Every
used actor ID and tag must be declared. The selected Profile source supplies
the twelve standard types; do not copy them into project files. Run
`wayfinder get` and commit its metadata-only `wayfinder.lock` before
validation. A later `validate` does not fetch or update it. Do not use
`captures` as a tag merely because a concept cites evidence.

## `knowledge/index.md`

````markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
````

Other root concepts are grouped by exact `type`. Standard groups follow the
base Profile manifest order; custom groups follow in lexical order. Immediate
subject directories appear under `# Directories`. The subject-placement rule
and the Profile-defined directory names remain unchanged, with the optional
`computations/` added for Attested Computation concepts (Profile §3.6).

## `knowledge/log.md`

````markdown
# Knowledge Log

## <YYYY-MM-DD>

* **Initialization**: Established the knowledge bundle under Bitwild Profile 2026.3.
````

## Captures

Seed only when the project has raw source material (see SKILL.md step 4a).
`captures/` sits beside `knowledge/`, is not an OKF bundle, and carries no
frontmatter. One package per source event or delivery, named
`<YYYY-MM-DD>-<channel>-<slug>` where `<channel>` is `meeting`, `thread`, or
`delivery` and the date is when it happened (meeting day, thread start, day files
were received). Originals keep their names and are never edited.

### `captures/index.md`

````markdown
# Captures

Evidence layer: originals are never edited; canonical knowledge lives in
`knowledge/`. Newest first.

| Package | Channel | Happened | Contents |
|---------|---------|----------|----------|
| [<YYYY-MM-DD>-<channel>-<slug>](<YYYY-MM-DD>-<channel>-<slug>/) | <channel> | <YYYY-MM-DD> | <one line> |
````

### `captures/<package>/intake.md`

````markdown
# <YYYY-MM-DD> <short title>

- Channel: meeting | thread | delivery
- Happened: <YYYY-MM-DD> (thread: started <date>, export current through <date>)
- Captured: <YYYY-MM-DD> by <actor>
- Participants: <names (organization)>; for a delivery, Sent by <name (organization)>
- Originals: <filename> (sha256 <hash>), one per line
- Sensitivity: none | commercial terms present (not reproduced) | personal or member-level data

## Summary
<3–6 sentences>

## Fed into knowledge/
<bullets linking the concepts this capture supports, or "none yet">

## Contradicts or corrects earlier captures
<bullets, or "none noted">

## Does not settle
<bullets, or "none noted">
````

Sensitivity records which visibility decision the user confirmed when the
originals were added; it describes the material, and grants no access control of
its own.

A capture that produced no durable outcome still gets an intake note with
"none yet"; that is a correct result, not a gap.
