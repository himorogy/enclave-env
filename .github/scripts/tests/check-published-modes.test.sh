#!/usr/bin/env bash
#
# .github/scripts/check-published-modes.sh の判定を、実物の npm レジストリにも
# pnpm pack にも頼らず検証する。tarball は tar コマンドで直接組み立てる。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-published-modes.sh"

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  ok   %s\n' "$1"
}

ng() {
	FAIL=$((FAIL + 1))
	printf '  FAIL %s\n' "$1" >&2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_tarball <name> — $WORK/src の中身を $WORK/<name>.tgz へ固める。
make_tarball() {
	tar -C "$WORK/src" -czf "$WORK/$1.tgz" .
}

reset_src() {
	rm -rf "$WORK/src"
	mkdir -p "$WORK/src"
}

# --- 正しい一覧 ----------------------------------------------------------------

echo "正しい一覧"

reset_src
printf '#!/bin/sh\necho hi\n' >"$WORK/src/run.sh"
chmod 755 "$WORK/src/run.sh"
printf '{}\n' >"$WORK/src/data.json"
chmod 644 "$WORK/src/data.json"
make_tarball ok

if "$CHECK" "$WORK/ok.tgz" >/dev/null 2>&1; then
	ok "shebang -> 755、非 shebang -> 644 の一覧を通す"
else
	ng "shebang -> 755、非 shebang -> 644 の一覧を通す"
fi

# --- 否定対照: この検査に検知能力があること --------------------------------------

echo "否定対照"

reset_src
printf '#!/bin/sh\necho hi\n' >"$WORK/src/run.sh"
chmod 644 "$WORK/src/run.sh"
make_tarball exec-as-plain

out="$("$CHECK" "$WORK/exec-as-plain.tgz" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'run.sh'; then
	ok "否定対照: shebang があるのに 644 の tarball を検知する"
else
	ng "否定対照: shebang があるのに 644 の tarball を検知する (rc=$rc out=$out)"
fi

reset_src
printf '{}\n' >"$WORK/src/data.json"
chmod 755 "$WORK/src/data.json"
make_tarball plain-as-exec

out="$("$CHECK" "$WORK/plain-as-exec.tgz" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'data.json'; then
	ok "否定対照: shebang が無いのに 755 の tarball を検知する"
else
	ng "否定対照: shebang が無いのに 755 の tarball を検知する (rc=$rc out=$out)"
fi

# 一部だけ合っていても、混ざっていれば全体として落ちる。
reset_src
printf '#!/bin/sh\necho hi\n' >"$WORK/src/run.sh"
chmod 755 "$WORK/src/run.sh"
printf '{}\n' >"$WORK/src/data.json"
chmod 755 "$WORK/src/data.json"
make_tarball mixed

if "$CHECK" "$WORK/mixed.tgz" >/dev/null 2>&1; then
	ng "否定対照: 一致する行と一致しない行が混在するとき全体を落とす"
else
	ok "否定対照: 一致する行と一致しない行が混在するとき全体を落とす"
fi

# --- 0 件走査 --------------------------------------------------------------------

echo "0件走査"

reset_src
mkdir -p "$WORK/src/empty-dir"
make_tarball empty

out="$("$CHECK" "$WORK/empty.tgz" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '0 件'; then
	ok "0 件走査で通さない"
else
	ng "0 件走査で通さない (rc=$rc out=$out)"
fi

# --- 入力の異常 ------------------------------------------------------------------

echo "入力の異常"

if "$CHECK" "$WORK/does-not-exist.tgz" >/dev/null 2>&1; then
	ng "存在しない tarball を指すと失敗する"
else
	ok "存在しない tarball を指すと失敗する"
fi

if "$CHECK" >/dev/null 2>&1; then
	ng "引数なしは usage で失敗する"
else
	ok "引数なしは usage で失敗する"
fi

# --- result ----------------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
