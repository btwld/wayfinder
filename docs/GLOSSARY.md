# Wayfinder glossary

The shared language for validating Open Knowledge Format bundles against
Profiles with wayfinder.

## Language

**OKF Specification**:
The authoritative Open Knowledge Format specification. The engine contract and
every Profile build on it and cannot redefine or weaken its meaning.
_Avoid_: Base profile, upstream profile

**Engine contract**:
The [implementation guide](../implementation/okf-implementation-guide.md) and the
JSON Schemas under [`schemas/`](schemas/). It says what a Profile package is and
how wayfinder selects, evaluates, and reports on one. It ranks below OKF and
above every Profile.
_Avoid_: Profile text
