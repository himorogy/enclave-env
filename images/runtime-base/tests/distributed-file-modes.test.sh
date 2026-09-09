#!/usr/bin/env bash
#
# 配布物 (npm パッケージとして配られる面と、ホスト・利用側リポジトリへ配られる
# テンプレート) の file mode の検査。
#
# 配布物は受け取った側の手元でそのまま使われる。実行ビットが落ちていると、
# 利用側は最初のコマンドで止まり、そこから先の検証に着手すらできない。実際に
# host-run.sh が mode 100644 で記録されたまま配られ、clone した全ホストで
# `karakuri-run` が失敗した。packages/egress-guard/scripts/init-project-firewall.sh は
# templates/proxy/Dockerfile が絶対パスで直接実行するので、この面では利用側の
# イメージのビルドが落ちる形で出る。
#
# 検査の対象は working tree ではなく git の index である。配られるのは
# clone や git archive、npm pack の結果であり、そこに載るのは index が持って
# いる mode だからである。working tree 側の mode は、exec ビットを持てない
# ファイルシステムや core.fileMode=false の環境で簡単に食い違う。
#
# 見るのは「実行して使うもの」と「読み込んで使うもの」の区別と mode の一致で
# ある。判定は shebang の有無で代用する——これは検査の手段であって、約束の
# 一部ではない（「実行するスクリプトには shebang を書く」という別の規約を
# 足しているのではない）。ファイルの一覧を持たないのは、区別が既にファイル
# 自身に書かれているためである。一覧を別に置くと同じ判断の二重管理になり、
# ファイルが増えるたび一覧の更新漏れという別の壊れ方を作る。対象はディレクトリ
# の単位でだけ書く。
#
# 中身も index から読む。working tree の shebang と index の mode を突き
# 合わせると、どちらか一方だけがコミットされた状態で判定がずれる。
#
# images/runtime-base/bin と images/runtime-base/shims は配布物に見えるが、
# この基準が当たらない面である。配られるのは clone の結果ではなくイメージで
# あり、実行権は Dockerfile の chmod がビルド時に付ける。shebang を持ちながら
# index が 100644 のファイルがそこに在るのは設計で、docs/guarantees.md の
# C-2b がそれを約束として持っている。
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# 台帳「公開面の定義」のうち、ファイルとして配られる面。
TARGET_DIRS=(
	packages/env-guard/bin
	packages/env-guard/hooks
	packages/egress-guard/scripts
	packages/egress-guard/templates
	images/runtime-base/templates/host
	images/runtime-base/templates/project
)

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

die() {
	printf 'FATAL %s\n' "$1" >&2
	exit 1
}

# expected_mode <blob sha> — 期待する mode を stdout に出す。
# blob が読めなければ空を出す (呼び出し側が失敗として扱う)。
expected_mode() {
	local head2
	git -C "$REPO_ROOT" cat-file -e "$1" 2>/dev/null || return 0
	head2="$(git -C "$REPO_ROOT" cat-file blob "$1" 2>/dev/null | dd bs=1 count=2 2>/dev/null)"
	if [ "$head2" = '#!' ]; then
		printf '100755\n'
	else
		printf '100644\n'
	fi
}

# check_modes — `git ls-files -s` 形式の一覧を stdin から読み、期待と違う行を
# stdout に出す。違反が無ければ何も出さない。
#
# 一覧を引数ではなく stdin で受けるのは、下の否定対照で壊した一覧を流し込んで
# 検知能力を確かめるためである。
check_modes() {
	local line mode sha path expected rest
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		mode="${line%% *}"
		rest="${line#* }"
		sha="${rest%% *}"
		path="${line#*$'\t'}"
		expected="$(expected_mode "$sha")"
		if [ -z "$expected" ]; then
			printf '%s: blob %s が読めない\n' "$path" "$sha"
		elif [ "$mode" != "$expected" ]; then
			if [ "$expected" = 100755 ]; then
				printf '%s: shebang があるのに mode %s (期待 100755)\n' "$path" "$mode"
			else
				printf '%s: shebang が無いのに mode %s (期待 100644)\n' "$path" "$mode"
			fi
		fi
	done
}

# listing_of <ディレクトリ> — 配下の tracked ファイルを `git ls-files -s` 形式で
# stdout に出す。存在しないディレクトリでは空を出す。
listing_of() {
	git -C "$REPO_ROOT" ls-files -s -- "$1"
}

# count_lines <文字列> — 行数を stdout に出す。空文字列を分けているのは、
# printf に通すと 0 行が 1 行に化けるためである。
count_lines() {
	if [ -z "$1" ]; then
		printf '0\n'
	else
		printf '%s\n' "$1" | wc -l | tr -d ' '
	fi
}

# --- 本番の一覧 ------------------------------------------------------------------

command -v git >/dev/null 2>&1 || die "git が無いので index の mode を読めない"

# 対象ディレクトリの綴りを間違えても、対象が丸ごと移動しても、走査結果が 0 件
# なら「全部一致」と同じ緑になる。
LISTING=""
for dir in "${TARGET_DIRS[@]}"; do
	listing="$(listing_of "$dir")" || die "git ls-files が失敗した ($dir)"
	count="$(count_lines "$listing")"
	if [ "$count" -ge 1 ]; then
		ok "$dir の tracked ファイルを $count 件読んだ"
	else
		ng "$dir の tracked ファイルが 0 件 (綴り違いか、対象が移動した)"
	fi
	[ -z "$listing" ] || LISTING="${LISTING}${listing}"$'\n'
done

VIOLATIONS="$(printf '%s' "$LISTING" | check_modes)"
if [ -z "$VIOLATIONS" ]; then
	ok "配布物の mode が、実行して使うものと読み込んで使うものの区別と一致する"
else
	ng "配布物の mode が、実行して使うものと読み込んで使うものの区別と一致する"
	printf '%s\n' "$VIOLATIONS" >&2
fi

# --- 否定対照: この検査に検知能力があること ----------------------------------------
#
# 「検査が緑であること」と「検査に検知能力があること」は別である。既知の
# 壊れ方を流し込んで、実際に引っかかることを確かめる。
#
# blob は実在のものを使う。shebang を読むのは index の中身なので、作り話の
# sha では判定そのものが走らない。

blob_of() {
	git -C "$REPO_ROOT" ls-files -s -- "$1" | awk '{print $2}'
}

HOST_DIR="images/runtime-base/templates/host"
SHEBANG_BLOB="$(blob_of "$HOST_DIR/host-run.sh")"
PLAIN_BLOB="$(blob_of "$HOST_DIR/karakuri.sh")"
[ -n "$SHEBANG_BLOB" ] || die "否定対照の材料 (host-run.sh) が見つからない"
[ -n "$PLAIN_BLOB" ] || die "否定対照の材料 (karakuri.sh) が見つからない"

# 実際に踏んだ壊れ方。shebang を持つスクリプトが 100644 で記録されている。
sample="100644 $SHEBANG_BLOB 0	$HOST_DIR/host-run.sh"
if [ -n "$(printf '%s\n' "$sample" | check_modes)" ]; then
	ok "否定対照: 実行して使うスクリプトの 100644 を検知する"
else
	ng "否定対照: 実行して使うスクリプトの 100644 を検知する"
fi

# 逆向き。source されるだけのファイルに実行ビットが立っている。
sample="100755 $PLAIN_BLOB 0	$HOST_DIR/karakuri.sh"
if [ -n "$(printf '%s\n' "$sample" | check_modes)" ]; then
	ok "否定対照: 読み込んで使うファイルの 100755 を検知する"
else
	ng "否定対照: 読み込んで使うファイルの 100755 を検知する"
fi

# symlink (120000) も期待と一致しないので落ちる。配布物の中身がリポジトリの
# 外を指す形に差し替わったときに素通しにしない。
sample="120000 $SHEBANG_BLOB 0	$HOST_DIR/dock.sh"
if [ -n "$(printf '%s\n' "$sample" | check_modes)" ]; then
	ok "否定対照: 100644 / 100755 以外の mode を検知する"
else
	ng "否定対照: 100644 / 100755 以外の mode を検知する"
fi

# index に無い blob を指す行は、shebang が読めないので判定できない。
# 「読めなかったから通す」へ倒れないことを確かめる。
sample="100755 0000000000000000000000000000000000000000 0	$HOST_DIR/ghost.sh"
if [ -n "$(printf '%s\n' "$sample" | check_modes)" ]; then
	ok "否定対照: 中身を読めない行を通さない"
else
	ng "否定対照: 中身を読めない行を通さない"
fi

# 誤検知の対照。正しい組み合わせは通ること。
sample="100755 $SHEBANG_BLOB 0	$HOST_DIR/host-run.sh
100644 $PLAIN_BLOB 0	$HOST_DIR/karakuri.sh"
if [ -z "$(printf '%s\n' "$sample" | check_modes)" ]; then
	ok "否定対照: 正しい mode の一覧を誤検知しない"
else
	ng "否定対照: 正しい mode の一覧を誤検知しない"
fi

# 綴りを間違えたディレクトリは、エラーではなく空の一覧として返ってくる。上の
# 歯止めが働くのはこの形に対してである。
if [ "$(count_lines "$(listing_of "${HOST_DIR}s")")" = 0 ]; then
	ok "否定対照: 綴りの違うディレクトリは 0 件として出る"
else
	ng "否定対照: 綴りの違うディレクトリは 0 件として出る"
fi

# --- result ----------------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
