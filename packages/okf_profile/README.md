# okf_profile

The OKF profile toolchain — checks a knowledge bundle against its declared
Concepta OKF Profile release through the `okfp` command-line interface.

```bash
dart run okf_profile:okfp validate knowledge
# Machine-readable output:
dart run okf_profile:okfp validate knowledge --output json
```

The command runs the independent OKF check and every deterministic rule
selected by the bundle's Profile declaration. Results, exit codes, and finding
identifiers are defined by the
[implementation guide §4](https://github.com/conceptadev/wayfinder/blob/main/implementation/okf-implementation-guide.md);
judgment rules are reported `UNASSESSED` and belong to Profile Review. The
profile itself, the guide, and the skill family live in the
[repository root](https://github.com/conceptadev/wayfinder).

## Application API

`package:okf_profile/okf_profile.dart` exports `ProfileValidator` and its result
contracts for applications such as [Wayfinder](../wayfinder/README.md). Both CLIs
share this validation implementation, including JSON states and exit codes.
