#!/bin/sh
# Tests for scripts/init-check-prod.sh

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$SCRIPT_DIR/scripts/init-check-prod.sh"

PASS=0
FAIL=0

assert_exit() {
  name=$1
  expected=$2
  actual=$3
  if [ "$actual" -eq "$expected" ]; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

run() {
  dir=$1
  fake_bin=$2
  if [ -n "$fake_bin" ]; then
    (cd "$dir" && PATH="$fake_bin:$PATH" sh "$SCRIPT" >/dev/null 2>&1)
  else
    (cd "$dir" && sh "$SCRIPT" >/dev/null 2>&1)
  fi
}

make_fake_docker() {
  output=$1
  dir=$(mktemp -d)
  if [ -n "$output" ]; then
    printf '#!/bin/sh\necho "%s"\n' "$output" > "$dir/docker"
  else
    printf '#!/bin/sh\n' > "$dir/docker"
  fi
  chmod +x "$dir/docker"
  echo "$dir"
}

# no enclave-env → exit 0 (skip with warning)
WORK=$(mktemp -d)
run "$WORK"
assert_exit "no enclave-env → exit 0" 0 $?
rm -rf "$WORK"

# DEV_CONTAINER_NAME not set → exit 0
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
run "$WORK"
assert_exit "DEV_CONTAINER_NAME not set → exit 0" 0 $?
rm -rf "$WORK"

# DEV_CONTAINER_NAME set, container not running → exit 0
WORK=$(mktemp -d)
printf 'MODE=single\nDEV_CONTAINER_NAME=my-dev\n' > "$WORK/enclave-env"
FAKE=$(make_fake_docker "")
run "$WORK" "$FAKE"
assert_exit "dev container not running → exit 0" 0 $?
rm -rf "$WORK" "$FAKE"

# DEV_CONTAINER_NAME set, container running → exit 1
WORK=$(mktemp -d)
printf 'MODE=single\nDEV_CONTAINER_NAME=my-dev\n' > "$WORK/enclave-env"
FAKE=$(make_fake_docker "my-dev")
run "$WORK" "$FAKE"
assert_exit "dev container running → exit 1" 1 $?
rm -rf "$WORK" "$FAKE"

echo ""
echo "init-check-prod.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
