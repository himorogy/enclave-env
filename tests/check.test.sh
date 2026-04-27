#!/bin/sh
# Tests for scripts/check.sh

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CHECK_SH="$SCRIPT_DIR/scripts/check.sh"

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

WORK=$(mktemp -d)
cd "$WORK" || exit 1
git init -q
git config user.email "test@test.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# no staged env files
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit "no staged env files → exit 0" 0 $?

# encrypted .env.production → pass
printf 'DOTENV_PUBLIC_KEY=abc\nKEY=encrypted:abc\n' > .env.production
git add .env.production
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit "encrypted .env.production → exit 0" 0 $?
git restore --staged .env.production

# unencrypted .env.production → fail
printf 'DOTENV_PUBLIC_KEY=abc\nDATABASE_URL=postgres://localhost\n' > .env.production
git add .env.production
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit "unencrypted .env.production → exit 1" 1 $?
git restore --staged .env.production

# .env.keys → fail
printf 'DOTENV_PRIVATE_KEY=secret\n' > .env.keys
git add .env.keys
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit ".env.keys staged → exit 1" 1 $?
git restore --staged .env.keys

# encrypted secret.env.production → pass
printf 'DOTENV_PUBLIC_KEY=abc\nKEY=encrypted:abc\n' > secret.env.production
git add secret.env.production
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit "encrypted secret.env.production → exit 0" 0 $?
git restore --staged secret.env.production

# comments and empty lines in encrypted file → pass
printf '# comment\nDOTENV_PUBLIC_KEY=abc\n\nKEY=encrypted:abc\n' > .env.production
git add .env.production
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit "comments and empty lines in encrypted file → exit 0" 0 $?
git restore --staged .env.production

# .env.container.example is skipped
mkdir -p .devcontainer/dev
printf 'API_KEY=your-key-here\n' > .devcontainer/dev/.env.container.example
git add .devcontainer/dev/.env.container.example
sh "$CHECK_SH" >/dev/null 2>&1
assert_exit ".env.container.example skipped → exit 0" 0 $?
git restore --staged .devcontainer/dev/.env.container.example

cd / && rm -rf "$WORK"

echo ""
echo "check.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
