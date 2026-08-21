# Concepta OKF Profile Glossary

The shared language for applying Concepta's company-wide conventions to Open
Knowledge Format bundles.

## Language

**OKF Specification**:
The authoritative Open Knowledge Format specification on which the Concepta OKF
Profile is built. The Profile cannot redefine or weaken its meaning.
_Avoid_: Base profile, upstream profile

**Concepta OKF Profile**:
Concepta's versioned, company-wide conventions for using OKF consistently
without changing OKF's meaning.
_Avoid_: Format, generic Profile protocol

**Profile Declaration**:
The machine-readable selector in a Profiled Bundle that identifies the Concepta
OKF Profile release it follows. It does not define or override that release's rules.
_Avoid_: Rule manifest, Profile configuration

**Profiled Bundle**:
An OKF bundle that selects a Concepta OKF Profile release and is evaluated
against both the OKF Specification and that release.
_Avoid_: Profile bundle

**OKF Conformance**:
The judgment, made exclusively under the OKF Specification, that a bundle meets
OKF's conformance requirements.
_Avoid_: Base acceptance

**Profile Conformance**:
The judgment that an OKF-conformant Profiled Bundle satisfies the enforceable
requirements of its declared Concepta OKF Profile release.
_Avoid_: OKF conformance, policy acceptance

**Profile Validation**:
The composed judgment that succeeds only when a Profiled Bundle is both
OKF-conformant and Profile-conformant.
_Avoid_: OKF validation

**Deterministic Rule**:
A Profile rule whose satisfaction can be determined reliably from the bundle
and its declared release. Its normative force is independent of its assessment mode.
_Avoid_: Judgment Rule, heuristic

**Judgment Rule**:
A Profile rule that requires contextual interpretation by a human or agent. It
may be a requirement or a recommendation and is not claimed as a CLI check.
_Avoid_: Deterministic Rule, automatic rule

**Profile Review**:
A contextual assessment by a human or agent against the Profile's Judgment
Rules. It is distinct from deterministic validation.
_Avoid_: Profile Validation, deterministic finding
