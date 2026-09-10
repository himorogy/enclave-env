---
status: open
type: test
base: main
targets:
  - docs/guarantees.md
  - images/runtime-base/tests/distributed-file-modes.test.sh
  - images/runtime-base/tests/host-file-modes.test.sh
  - images/runtime-base/tests/run.sh
verify:
  - pnpm lint
  - pnpm lint:sh
  - pnpm test
---

# 配布物の file mode の検査を、公開面の定義に載る全体へ広げる

## 内容

0014a が入れた `host-file-modes.test.sh` は、対象ディレクトリを
`images/runtime-base/templates/host` に固定している。台帳の公開面の定義には他にも配布物が
あり、そちらは検査されていない。**現に壊れているものは無いが、0014a が直したのと同じ壊れ方
（配布物の mode が落ちたまま配られ、受け取った側が最初のコマンドで止まる）を止める仕組みが
片方の面にしか無い。**

0020 の実装中に判明した。0020 が `packages/egress-guard/templates/proxy/` を新設し、その
`Dockerfile` が `packages/egress-guard/scripts/init-project-firewall.sh` を**絶対パスで直接
実行する**ようになったため、この面の実行ビットが落ちるとビルドが失敗する経路ができた。

### 検査対象の現状

台帳「公開面の定義」の各面について、index の mode を 0014a と同じ基準（shebang があれば
100755、無ければ 100644）で突き合わせた結果。

- **A. `@himorogy/env-guard`**（`bin/` `hooks/`）— 検査なし。現状は一致
- **B. `@himorogy/egress-guard`**（`scripts/` `templates/`）— 検査なし。現状は一致
- **D. ホストと利用側リポジトリへ配布されるテンプレート** — `templates/host/` だけ 0014a が
  検査している。`templates/project/` は検査なし（現状は一致）
- **C-1 / C-2. `runtime-base` イメージへ焼かれるもの** — **この基準を当ててはならない面。**
  `bin/git-auth-check` / `bin/git-credential-gh-token` / `bin/karakuri-context` は index が
  100644 で shebang を持つが、これは設計であり台帳 C-2b に明記がある（「リポジトリ上の
  パーミッションが 644 のものが含まれ、実行権はイメージのビルド時に初めて付く」）。
  Dockerfile が `chmod 0755` する

### このチケットで行うこと

**1. 対象ディレクトリを一覧ではなくディレクトリの列挙で広げる。** 0014a の「ファイルの一覧を
別に持たない」という判断は維持する——区別は既にファイル自身（shebang の有無）に書かれており、
一覧を置くと更新漏れという別の壊れ方を作る。広げるのはディレクトリの側だけ。

対象に加えるのは、npm パッケージとして配られる面（`packages/*/` の `files` に載るもの）と、
ホストへ配られるテンプレートの残り（`templates/project/`）である。

**2. イメージへ焼かれる面を対象外とし、その理由を検査の中に書く。** `images/runtime-base/bin`
と `images/runtime-base/shims` は「配布物」に見えるが、配られるのは clone の結果ではなく
イメージであり、実行権はビルド時に付く。**対象外であることを黙って落とすのではなく、なぜ
この面だけ基準が当たらないのかを書く**——書かないと、次に一覧を見た人が「漏れている」と
判断して足し、誤検知でテストが赤くなる。

**3. 0 件走査で通さない。** 対象ディレクトリの綴りを間違えても、走査結果が 0 件なら
「全部一致」と同じ緑になる。各対象ディレクトリについて、1 件以上を実際に見たことを確かめる。

**4. ファイル名を対象の実態に合わせる。** `host-file-modes.test.sh` は `host/` 限定だった頃の
名前で、対象を広げると名が体を表さなくなる。`run.sh` の呼び出しと台帳 §23 の見出しも同時に
揃える。

### やらないこと

- **`packages/*/package.json` の `files` を読んで対象を導出しない。** `files` は npm の配布
  範囲であって「実行して使うか」の区別ではなく、ディレクトリの列挙より複雑な割に得るものが
  無い。対象は検査の中にディレクトリで書く
- **`init-project-firewall.sh` を `bin` フィールド経由の配布に変えない。** `egress-guard` が
  `bin` を持たないのは現在の設計で、3 箇所（`runtime-base` の Dockerfile、README の手順、
  `templates/proxy/Dockerfile`）が絶対パスで参照している。変えるなら別の作業単位
- 現に壊れているファイルの修正。**このチケットの時点では 0 件である**（0014a が `host-run.sh`
  を直し、それ以外は一致している）。検査を広げた結果として何か落ちたら、それは前提が変わった
  ということなので、そこで判断する
- `images/devcontainer-base/` の配下。公開面 E は「対応するテストを持たず、何を約束にすべきかも
  定めていない」として候補層に置かれている面であり、mode だけ先に約束するのは順序が逆

## 保証

### 新たに宣言する保証

- npm パッケージとして配られる面（`@himorogy/env-guard` の `bin` と `hooks`、
  `@himorogy/egress-guard` の `scripts` と `templates`）でも、実行して使うスクリプトは受け取った
  側でそのまま実行でき、読み込んで使うファイルは実行可能にならない。**受け取った側が mode を
  直す手順を要求されることはない**（テスト: 対象を広げた検査の該当ケース。テスト名は実装時に
  確定する）

### 維持する保証

- 台帳 §23 の 2 行（0014a が宣言した、ホストへ配るテンプレートについての約束）。**範囲を広げる
  だけで、`host/` について約束していることは 1 行も変えない**
- 台帳 C-2b の「`secrets-ingest.sh`・`git-askpass`・`git-auth-check`・`git-credential-gh-token`・
  `karakuri-context`・`env-guard-scan` が `/usr/local/bin` へ置かれ、実行可能である（リポジトリ上の
  パーミッションが 644 のものが含まれ、実行権はイメージのビルド時に初めて付く）」——**この面を
  検査の対象外に置くのは、この行と衝突させないためである**

### 廃止する保証

- なし。§23 の 2 行は範囲が広がるだけで、取り下げる約束は無い。**行の文面が `host/` に限定されて
  いる場合は、限定を外す形の書き換えになる**——約束の取り下げではないので廃止には数えない
