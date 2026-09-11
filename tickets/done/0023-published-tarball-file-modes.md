---
status: close
type: fix
base: main
targets:
  - .github/scripts/check-published-modes.sh
  - .github/scripts/tests/check-published-modes.test.sh
  - .github/workflows/release.yml
  - docs/conventions.md
  - docs/guarantees.md
  - package.json
  - packages/egress-guard/package.json
  - packages/env-guard/package.json
verify:
  - pnpm lint
  - pnpm lint:sh
  - pnpm test
---

# npm へ公開される tarball の実行ビットが落ちるのを止め、公開の直前に検査する

## 内容

**公開済みのパッケージが現に壊れている。** `@himorogy/egress-guard` の
`scripts/init-project-firewall.sh` は、レジストリ上で次の mode で配られている。

```
0.1.0  -rwxr-xr-x   docs/secure-publish.md §7.4 の例外（初回のみ手元から npm publish）
0.1.1  -rw-r--r--   .github/workflows/release.yml の pnpm publish
0.2.0  -rw-r--r--   同上
```

git の index では `100755` である。落ちているのは publish の経路である。

**未発火の被害が 1 件ある。** `packages/egress-guard/templates/proxy/Dockerfile` は
`npm install -g @himorogy/egress-guard` した実体を絶対パスで**直接実行し、chmod を挟まない**。
0.3.0 を CI から公開すると、L7 sidecar を組む利用者のビルドが EACCES で落ちる。

**表面化していない理由。** README の導入手順と `images/runtime-base/Dockerfile` はどちらも
`cp` の直後に `chmod 755` を明示していて、そこで吸収されている。

**`@himorogy/env-guard` にも同じ壊れ方がある。** `bin` フィールドが指すのは
`bin/env-guard.js` と `bin/env-guard-scan` の 2 つだけで、shebang を持つ `hooks/pre-commit` は
どちらの経路にも載っていない。レジストリ上の 0.1.0 が 755 なのは
`docs/secure-publish.md` §7.4 の例外（初回のみ手元から `npm publish`）で出たためであり、
CI 経路から出た版ではない。台帳 §23 の 3 行目は `@himorogy/env-guard` の `hooks` を名指しで
約束しているので、この面も次の版から満たさなくなる。

**既存の検査では原理的に届かない。** `images/runtime-base/tests/distributed-file-modes.test.sh`
は git の index を読む。index が正しいまま publish 側で落ちる今回の形は、緑のまま通る。

### 原因は pnpm の設計であって、事故ではない

pnpm 11.25.0 の実装（`pnpm/dist/pnpm.mjs` の `packPkg`）は、tarball に入れる各ファイルの
mode を**ソースの mode を読まずに決めている**。

```js
const isExecutable = bins.some((bin) => path.relative(bin, source) === "");
const mode = isExecutable ? 493 : 420;   // 0o755 : 0o644
```

`bins` に入るのは 2 つだけである——`package.json` の `bin` フィールドが指すファイルと、
`publishConfig.executableFiles` に列挙されたファイル。**それ以外は、元が 755 でも 644 になる。**
同じ関数が mtime も固定値へ正規化しており、**入力によらず同じ tarball を出す**設計である。

実測（2026-09-10、pnpm 11.25.0 / npm 11.17.0）:

- `chmod 755` のファイルを `pnpm pack` → tarball 内は 644。`npm pack` は 755 のまま
- `publishConfig.executableFiles` に列挙すると、**ソースが 644 でも** tarball 内は 755

**`@himorogy/egress-guard` は `bin` フィールドを持たない**（`files` は `scripts` / `templates` /
`docs` / `README.md`）。したがって `scripts/init-project-firewall.sh` はどちらの経路にも
載っておらず、必ず 644 になる。

**`upload-artifact` / `download-artifact` の zip 往復は原因ではない。** pnpm がソースの mode を
読まない以上、往復で mode が落ちていても結果は変わらない。**この経路を検証する必要は無い。**

### 経路

- **前方**（publish の手前）— `prepare` がパッケージ名・版・ディレクトリを決め、`build` が
  `checkout` → `pnpm install --frozen-lockfile --ignore-scripts` → `pnpm --filter <name> run
  --if-present build` → `upload-artifact` で公開対象のディレクトリを退避する
- **publish** — `checkout` → `download-artifact` で上書き → `pnpm/action-setup` →
  `setup-node` → `pnpm publish --access public --ignore-scripts --no-git-checks`
- **後方**（publish の後）— レジストリから引けるようになったかを 10 回まで照会する。
  **このステップは公開の成否を左右しない**——publish が成功した時点で公開は済んでおり、
  取り消せない
- **参照**（配られた実体を使う側）— `packages/egress-guard/templates/proxy/Dockerfile`
  （直接実行・chmod なし）、`packages/egress-guard/README.md` の導入手順（`chmod 755` あり）、
  `images/runtime-base/Dockerfile`（`chmod 0755` あり）

### このチケットで行うこと

**1. `@himorogy/egress-guard` と `@himorogy/env-guard` の `publishConfig.executableFiles` に、
実行して使うスクリプトを宣言する。** pnpm が用意している正規の出口であり、これが直し方である。
`bin` フィールドに載っていない実行対象——egress-guard の `scripts/init-project-firewall.sh` と
env-guard の `hooks/pre-commit`——がこの宣言の対象である。

**2. 公開される tarball の mode を、公開の直前に検査する。** 検査は `pnpm publish` の**前**に
置き、落ちていたら公開しない。**公開は取り消せない**ので、検査を後ろに置くと「壊れたものが
公開された」ことを知るだけの検査になる（後方の照会ステップが既にその位置にあり、
コメントで自らそう書いている）。

期待する mode の導出は `distributed-file-modes.test.sh` と同じ基準——shebang があれば実行可能、
無ければ実行可能でない——とし、ファイルの一覧は持たない。**基準を 2 通り持たない**ことが要点で、
index を見る検査と tarball を見る検査が同じ規則で判定する。

**この検査は 1 の宣言が漏れることを想定して置く。** `executableFiles` は列挙なので、
**shebang を持つファイルが配布範囲（`files`）に増えたときの更新漏れ**が次の壊れ方になる。現に
今回壊れたのも、列挙そのものが無かったためである。**列挙を持たない基準（shebang）で列挙の結果を
検査する**という関係にあり、**機械が決めるのは 2 つの一致だけである**——どのファイルを実行させたいか
を決めるのは開発者であって、その判断は shebang という形で既にファイルに書かれている（一覧を別に
持たない理由は 0014a から一貫してここにある）。

**この基準には既知の限界がある。** shebang を持ちながら実行させたくないファイル——source される
前提で書かれ、エディタのために shebang を置いたもの——はこの区別で表現できず、検査は
`executableFiles` への宣言を要求する。**0014a から続く設計の性質であって、このチケットが新しく
持ち込む制約ではない**（index を見る検査が既に同じ判定をしている）。該当するファイルは現在
`@himorogy/egress-guard` の配布範囲に無い。出てきた時点で基準を見直す。

検査は `.github/scripts/` へ置き、その自己検証を `.github/scripts/tests/` へ置く
（`pin-lag.sh` と同じ組み方）。**0 件走査で通さない**——tarball の中に対象が 1 件も無ければ
落とす。

**3. `docs/conventions.md` に記録する。書くのは 2 つある。**

- **規約** — 「**実行して使うかどうかは shebang の有無で表明し、ファイルの一覧を別に持たない**」。
  これは 0014a が置いた判断で、`distributed-file-modes.test.sh` と今回の検査の**両方がこの規約に
  依存している**にもかかわらず、**現在形の文書のどこにも書かれていない**（追跡ファイルで
  `shebang` の語が出てくるのはテスト本体のコメントだけである）。規約を知らない人が、shebang を
  持つ内部ヘルパを配布範囲に足すと、検査は「宣言が漏れている」と言い、足した側にはそれが
  誤検知に見える。**検査が規約に依存しているなら、規約は検査と同じだけ読める場所に要る**
- **発見しにくい事実** — 「pnpm は tarball の mode をソースから読まず、`bin` と
  `publishConfig.executableFiles` だけを 755 にする。公開物の mode は index を見る検査では
  担保できず、publish の直前の tarball 検査で見る」。**担保の場所まで書く**——事実だけ置くと、
  次に読む人が「知っている前提」で通す

**4. 台帳の索引に、この検査を載せる。** §23 の 3 行目（0014b が宣言した npm パッケージ面の
約束）は**利用者の手元での実行可能性**を約束しており、publish 経路を含む。今回はその約束に
裏付けを足す変更であって、新しい約束ではない。索引の粒度はテストファイル単位なので、
§23 の出典に今回の検査を加える形になる。

### やらないこと

- **`pnpm publish` を `npm publish` に替えない。** npm はソースの mode を読むので、
  今度は `upload-artifact` / `download-artifact` の zip 往復が効いてくる。**現在は無関係な経路を、
  自分から関係させる方向の変更である。** `publishConfig.executableFiles` は pnpm がこの用途に
  用意しているものであり、道具を替える理由が無い
- **公開済みの 0.1.1 / 0.2.0 の修復。** npm は同じ版の再公開を許さない。直った実体が配られるのは
  次の版からである。**この 2 版が壊れていること自体は仕様どおりに直せない**ので、必要なら
  deprecate するかどうかを別途判断する
- **0.3.0 の公開そのもの。** このチケットは公開の経路を直すだけで、版を出すのは別の操作
- **`@himorogy/egress-guard` に `bin` フィールドを足さない。** `bin` を持たないのは現在の設計で、
  3 箇所（`runtime-base` の Dockerfile、README の手順、`templates/proxy/Dockerfile`）が
  絶対パスで参照している。変えるなら別の作業単位（0014b の「やらないこと」と同じ判断）
- **`distributed-file-modes.test.sh`（index を見る検査）の変更。** 見ている面が違うので、
  こちらは触らない。**同じ基準を共有するだけで、実装を共有しようとしない**——一方は
  `git ls-files -s`、他方は tarball の中身で、入力の形が違う
- **`templates/proxy/Dockerfile` に `chmod` を足して回避する。** 配られた実体が実行可能で
  あることが約束であり、利用者側で直すのは約束を弱める方向である

## 保証

### 新たに宣言する保証

- なし。**台帳 §23 の 3 行目が既に約束している**（「npm パッケージとして配られる面でも…受け取った
  側が mode を直す手順を要求されることはない」）。この変更はその約束に裏付けを足すもので、
  拘束力は増えない。台帳に触るのは索引に検査を載せるためである

### 維持する保証

- 台帳 §23 の 3 行目（起源 `0014b-public-surface-file-modes`）——**約束の文面は 1 語も変えない。**
  変わるのは、その約束を裏付ける検査が publish 経路まで届くようになることだけである
- 台帳 §23 の 1 行目・2 行目（起源 `0014a`）——ホストと利用側リポジトリへ配るテンプレートの面。
  今回は触らない
- 台帳「境界宣言 > 公開面の定義」の B（`@himorogy/egress-guard`）——面の列挙は変わらない
- `docs/secure-publish.md` §8 が記録している「公開に到達する経路は 1 本だけ」——検査を足すだけで
  経路は増やさない。§7.4 の例外（未公開パッケージの初回のみ手元から公開）もそのまま

### 廃止する保証

- なし。壊れている実物を約束に合わせる変更であり、取り下げる約束は無い
