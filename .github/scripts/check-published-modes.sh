#!/usr/bin/env bash
#
# .github/workflows/release.yml の build ジョブから、publish ジョブより前に
# 呼ばれる（build ジョブに置く理由は docs/conventions.md「配布物の実行可能性」）。
# tarball の中身を見るのは images/runtime-base/tests/distributed-file-modes.test.sh
# が見る git index とは別の層で、pnpm pack が mode をソースの mode から
# 独立に決めるため（発見しにくい事実も同節）。
#
# 期待 mode の基準は distributed-file-modes.test.sh と同じ（docs/conventions.md
# 「配布物の実行可能性」が正本）。ファイルの一覧はここでも持たない。
set -eu

usage() {
	cat >&2 <<'EOF'
usage: check-published-modes.sh <tarball>
EOF
	exit 64
}

die() {
	printf 'FATAL %s\n' "$1" >&2
	exit 1
}

# distributed-file-modes.test.sh の expected_mode と同じ基準（shebang の有無）。
expected_state() {
	local head2
	head2="$(dd bs=1 count=2 2>/dev/null)"
	if [ "$head2" = '#!' ]; then
		printf 'exec\n'
	else
		printf 'plain\n'
	fi
}

# 引数は `tar -tvf` の1列目（例: -rwxr-xr-x）。ディレクトリ・symlink 等、
# 通常ファイルでないエントリは other として走査対象から除く。
actual_state() {
	local perms="$1"
	case "$perms" in
		-??x*) printf 'exec\n' ;;
		-??-*) printf 'plain\n' ;;
		*) printf 'other\n' ;;
	esac
}

main() {
	[ $# -eq 1 ] || usage
	local tarball="$1"
	[ -f "$tarball" ] || die "tarball が見つからない: $tarball"

	local listing
	listing="$(tar -tvf "$tarball")" || die "tar の一覧取得に失敗した: $tarball"

	local count=0 fail=0
	local line perms path expected actual
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		perms="$(printf '%s' "$line" | awk '{print $1}')"
		actual="$(actual_state "$perms")"
		[ "$actual" != other ] || continue

		# 5列固定は GNU tar の `-tvf` 出力（owner/group が1列）が前提。
		# 列数が違う tar だと path がずれ、下の tar -xOf が失敗して騒がしく落ちる。
		path="$(printf '%s\n' "$line" | awk '{for (i = 1; i <= 5; i++) $i = ""; sub(/^ +/, ""); print}')"
		[ -n "$path" ] || continue

		count=$((count + 1))
		expected="$(tar -xOf "$tarball" "$path" 2>/dev/null | expected_state)"

		if [ "$expected" != "$actual" ]; then
			fail=$((fail + 1))
			if [ "$expected" = exec ]; then
				printf '%s: shebang があるのに mode %s (実行可能でない)\n' "$path" "$perms" >&2
			else
				printf '%s: shebang が無いのに mode %s (実行可能)\n' "$path" "$perms" >&2
			fi
		fi
	done <<EOF
$listing
EOF

	if [ "$count" -eq 0 ]; then
		die "tarball 内に検査対象の通常ファイルが 0 件だった: $tarball"
	fi

	if [ "$fail" -gt 0 ]; then
		printf '%s 件中 %s 件の mode が shebang の有無と一致しなかった\n' "$count" "$fail" >&2
		exit 1
	fi

	printf '%s 件を検査し、mode が shebang の有無と一致した: %s\n' "$count" "$tarball"
}

main "$@"
