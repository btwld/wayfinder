# Bitwild OKF Profile Glossary

The shared language for applying Bitwild's reusable conventions to Open
Knowledge Format bundles.

## Language

**OKF Specification**:
The authoritative Open Knowledge Format specification on which the Bitwild OKF
Profile is built. The Profile cannot redefine or weaken its meaning.
_Avoid_: Base profile, upstream profile

**Bitwild OKF Profile**:
Bitwild's versioned, reusable conventions for using OKF consistently
without changing OKF's meaning.
_Avoid_: Format, generic Profile protocol

**Profile Binding**:
The project-root `wayfinder.json` entry whose direct Git `source` and
`applies_to` paths select one exact Profile release for a whole bundle,
with additive project type, tag, and actor lookup extensions. It cannot
define or override Profile rules.
_Avoid_: Rule manifest, per-directory Profile

**Legacy Profile Declaration**:
The `profile.md` selector inside a 2026.2 bundle. It remains valid for that
release and does not define or override its rules.
_Avoid_: Current 2026.3 binding

**Profiled Bundle**:
An OKF bundle bound to a Bitwild or legacy Concepta OKF Profile release and evaluated
against both the OKF Specification and that release.
_Avoid_: Profile bundle

**OKF Conformance**:
The judgment, made exclusively under the OKF Specification, that a bundle meets
OKF's conformance requirements.
_Avoid_: Base acceptance

**Profile Conformance**:
The judgment that an OKF-conformant Profiled Bundle satisfies every `MUST` and
`MUST NOT` in its selected Profile release, regardless of assessment mode.
_Avoid_: OKF conformance, policy acceptance

**Automated Profile Validation**:
The model-independent CLI operation that reports OKF conformance and evaluates
the Profile's Deterministic Rules while explicitly leaving Judgment Rules unassessed.
_Avoid_: Complete Profile Assessment, Profile Review

**Deterministic Rule**:
A Profile rule whose satisfaction can be determined reliably from the bundle
and its selected release. Its normative force is independent of its assessment mode.
_Avoid_: Judgment Rule, heuristic

**Judgment Rule**:
A Profile rule that requires contextual interpretation by a human or agent. It
may be a requirement or a recommendation and is not claimed as a CLI check.
_Avoid_: Deterministic Rule, automatic rule

**Profile Review**:
A contextual assessment by a human or agent against the Profile's Judgment
Rules. It is distinct from deterministic validation.
_Avoid_: Automated Profile Validation, deterministic finding

**Profile Review Report**:
A structured, non-bundle summary of a Profile Review, suitable for the active
interaction or pull request. It records reasoning and escalations without becoming knowledge content.
_Avoid_: Bundle concept, conformance certificate

**Complete Profile Assessment**:
The combined evidence from Automated Profile Validation and Profile Review used
to assess all requirements of a Profiled Bundle.
_Avoid_: CLI result, OKF conformance

**Profile Toolchain**:
The validator, skill, and guides that apply the Bitwild OKF Profile through
deterministic validation and contextual review.
_Avoid_: Bitwild OKF Profile, OKF toolkit
