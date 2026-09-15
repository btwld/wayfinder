#!/bin/sh
# Platform detection is the part of install.sh that the real installation test
# (tool/verify_installer.py) cannot cover: that test only ever runs on a machine
# we publish a bundle for. Each case here runs install.sh with a uname that
# reports another machine.
#
# Every case stops at a check that precedes the first download, so the test
# needs no network and installs nothing. Cases that must clear the platform
# gate set an unusable WAYFINDER_VERSION and expect its rejection as proof.
set -eu
installer="$(cd "$(dirname "$0")" && pwd)/install.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
passed_gate='WAYFINDER_VERSION must be a published release version.'
export WAYFINDER_VERSION=unusable
export WAYFINDER_INSTALL_DIR="$test_root/bin"
export WAYFINDER_INSTALL_ROOT="$test_root/runtime"

# Runs install.sh against a reported machine and asserts how it fails.
assert_refusal() {
  system="$1"
  machine="$2"
  expected="$3"
  shim="$test_root/$system-$machine"
  mkdir -p "$shim"
  cat > "$shim/uname" <<SHIM
#!/bin/sh
case "\$1" in
  -s) echo '$system' ;;
  -m) echo '$machine' ;;
  *) echo 'install.sh asked uname something this test does not fake' >&2; exit 1 ;;
esac
SHIM
  chmod +x "$shim/uname"
  if output="$(PATH="$shim:$PATH" sh "$installer" 2>&1)"; then
    printf 'FAIL: %s-%s: the installer did not fail.\n' "$system" "$machine" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) printf 'OK: %s-%s\n' "$system" "$machine" ;;
    *)
      printf 'FAIL: %s-%s: expected a failure like "%s", got "%s".\n' \
        "$system" "$machine" "$expected" "$output" >&2
      exit 1
      ;;
  esac
}

# An unsupported machine is named, so it is never confused with a failed
# detection, the way an empty architecture probe was on Windows (#98).
assert_refusal Darwin x86_64 'Darwin-x86_64 has no prebuilt Wayfinder bundle'
assert_refusal Linux aarch64 'Linux-aarch64 has no prebuilt Wayfinder bundle'
# Both published platforms clear the gate.
assert_refusal Darwin arm64 "$passed_gate"
assert_refusal Linux x86_64 "$passed_gate"
printf 'PASS: install.sh platform detection and refusals.\n'
