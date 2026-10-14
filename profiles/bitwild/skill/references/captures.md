# The `captures/` evidence layer

Raw evidence lives in `captures/`, beside the bundle and never inside it:
transcripts, thread exports, and files a client delivered. `captures/` is
evidence, not knowledge. It is not an OKF bundle, carries no frontmatter, and
Wayfinder does not index or validate it.

Durable outcomes reach the bundle as concepts that cite a capture package in
`sources`. If a concept and a capture disagree, re-read the evidence and
correct any inaccurate concept.

## Packages

Keep one package per source event or delivery, named
`<YYYY-MM-DD>-<channel>-<slug>`. `<channel>` is `meeting`, `thread`, or
`delivery`. The date is when it happened: the meeting day, the thread start,
or the day files arrived.

- Each package holds an `intake.md` in the shape of the [seed](#seed)
  template.
- Originals keep their names and are never edited.
- Move material the repository already tracks into a package with `git mv`
  so history survives.
- Committing an original the repository does not track yet widens who can
  read it, because `captures/` inherits the repository's access controls.
  Name those files and confirm with the user that the material may live at
  that visibility before adding them. Leave the material where it is if the
  user declines.
- A capture that produced no durable outcome still gets an intake note that
  says "none yet". That is a correct result, not a gap.

## Seed

Seed `captures/` only when the project holds or will receive raw source
material. Skip it, and say so, otherwise.

`captures/index.md`:

````markdown
# Captures

Evidence layer: originals are never edited; canonical knowledge lives in
`knowledge/`. Newest first.

| Package | Channel | Happened | Contents |
|---------|---------|----------|----------|
| [<YYYY-MM-DD>-<channel>-<slug>](<YYYY-MM-DD>-<channel>-<slug>/) | <channel> | <YYYY-MM-DD> | <one line> |
````

`captures/<package>/intake.md`:

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

`Sensitivity` records which visibility decision the user confirmed when the
originals were added. It describes the material and grants no access control.

## Agent instructions block

Add this block to `AGENTS.md` under `## Agent skills` when `captures/` is
seeded:

```markdown
### Captures

Raw evidence (transcripts, thread exports, files the client sent) lives in
`captures/`, one dated package per event or delivery, each with an `intake.md`.
Originals there are never edited. `captures/` is evidence, not knowledge: it is
not an OKF bundle and Wayfinder does not index it. Durable outcomes reach
`knowledge/` as concepts that cite the package in `sources`; if a concept and a
capture disagree, re-read the evidence and correct any inaccurate concept.
```
