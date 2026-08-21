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

**Enforceable Requirement**:
A Profile `MUST` or `MUST NOT` whose satisfaction can be determined reliably
from the bundle and its declared release and therefore participates in CLI
conformance.
_Avoid_: Heuristic, judgment guidance

**Judgment Guidance**:
A Profile `SHOULD` or `SHOULD NOT` that requires contextual interpretation and
is taught or reviewed by humans and agents through skills and guides rather than
claimed as a deterministic CLI check.
_Avoid_: Enforceable Requirement, automatic rule

**Profile Review**:
A contextual assessment by a human or agent against Judgment Guidance. It may
recommend corrections but does not change OKF or Profile conformance.
_Avoid_: Profile Validation, deterministic finding
