#!/bin/sh
# Tests for scripts/init-check-dev.sh

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$SCRIPT_DIR/scripts/init-check-dev.sh"

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
  (cd "$dir" && sh "$SCRIPT" >/dev/null 2>&1)
}

# no enclave-env → exit 0 (warning)
WORK=$(mktemp -d)
run "$WORK"
assert_exit "no enclave-env → exit 0" 0 $?
rm -rf "$WORK"

# clean workspace → exit 0
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
run "$WORK"
assert_exit "clean workspace → exit 0" 0 $?
rm -rf "$WORK"

# encrypted .env.production → exit 0
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
printf 'DOTENV_PUBLIC_KEY=abc\nKEY=encrypted:abc\n' > "$WORK/.env.production"
run "$WORK"
assert_exit "encrypted .env.production → exit 0" 0 $?
rm -rf "$WORK"

# unencrypted .env.production → exit 1
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
printf 'DOTENV_PUBLIC_KEY=abc\nDATABASE_URL=postgres://localhost\n' > "$WORK/.env.production"
run "$WORK"
assert_exit "unencrypted .env.production → exit 1" 1 $?
rm -rf "$WORK"

# unencrypted secret.env.production → exit 1
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
printf 'DOTENV_PUBLIC_KEY=abc\nSECRET_KEY=plaintext\n' > "$WORK/secret.env.production"
run "$WORK"
assert_exit "unencrypted secret.env.production → exit 1" 1 $?
rm -rf "$WORK"

# .env.container with DOTENV_PRIVATE_KEY_PRODUCTION → exit 1
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
mkdir -p "$WORK/.devcontainer/dev"
printf 'DOTENV_PRIVATE_KEY_PRODUCTION=secret\n' > "$WORK/.devcontainer/dev/.env.container"
run "$WORK"
assert_exit ".env.container with prod key → exit 1" 1 $?
rm -rf "$WORK"

# .env.keys in workspace → exit 1
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
printf 'DOTENV_PRIVATE_KEY=secret\n' > "$WORK/.env.keys"
run "$WORK"
assert_exit ".env.keys in workspace → exit 1" 1 $?
rm -rf "$WORK"

# encrypted .env.production with comments/empty lines → exit 0
WORK=$(mktemp -d)
printf 'MODE=single\n' > "$WORK/enclave-env"
printf '# comment\nDOTENV_PUBLIC_KEY=abc\n\nKEY=encrypted:abc\n' > "$WORK/.env.production"
run "$WORK"
assert_exit "comments and empty lines in encrypted file → exit 0" 0 $?
rm -rf "$WORK"

echo ""
echo "init-check-dev.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
