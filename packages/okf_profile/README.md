# okf_profile

The OKF profile toolchain — checks a knowledge bundle against its declared
Concepta OKF Profile release through the `okfp` command-line interface.

```bash
dart run okf_profile:okfp validate knowledge
# Machine-readable output:
dart run okf_profile:okfp validate knowledge --output json
```

The command requires exactly one explicit bundle directory and inspects only
that directory. It runs the independent OKF check and every deterministic rule
selected by the bundle's Profile declaration. Exit `0` means those automated
checks passed; advisories remain non-blocking. Exit `1` means OKF or
deterministic Profile validation failed, and exit `2` reports usage, I/O, or an
unsupported Profile release.

Automated success is not complete Profile conformance: judgment rules are
reported `UNASSESSED` and belong to Profile Review. The profile itself, the
implementation guide, and the skill family live in the
[repository root](https://github.com/conceptadev/okf-profile).
