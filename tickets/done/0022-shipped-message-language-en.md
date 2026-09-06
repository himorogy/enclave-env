---
status: close
type: refactor
base: main
targets:
  - docs/conventions.md
  - images/runtime-base/README.md
  - images/runtime-base/bin/git-auth-check
  - images/runtime-base/bin/karakuri-context
  - images/runtime-base/bin/prod-entrypoint.sh
  - images/runtime-base/tests/git-credential.test.sh
  - images/runtime-base/tests/karakuri-context.test.sh
  - images/runtime-base/tests/verify-docker.sh
verify:
  - pnpm lint
  - pnpm lint:sh
  - pnpm test
---

# イメージに焼き込む出荷物の利用者向けメッセージを英語へ統一し、規約に載せる

## 内容

`images/runtime-base/bin` の3本が、標準出力・標準エラーへ日本語のメッセージを出している。
`images/devcontainer-base/bin/git-identity-setup` は `0018a-git-identity-after-inject` で英語へ
統一したが、その判断はスクリプト1本に閉じていて規約になっていない。runtime-base 側を同じ扱いに
揃え、あわせて `docs/conventions.md` に規約として1節を置く。

### 文言の書き換え

対象は3本。日本語を含む出力の位置は次のとおり（コメントは対象外）。

- `bin/git-auth-check` — 報告文を組み立てる変数代入 56 / 58 / 62 / 64 行。出力そのものは 67 行の1本
- `bin/karakuri-context` — 78 行（注入済みの鍵名の報告）、82 行（鍵が無い旨の1行）。
  102 / 104 行は元から英語で対象外
- `bin/prod-entrypoint.sh` — 64-66 / 121 / 125-128 / 134 / 153-156 / 213 / 216 / 259-260 /
  319-320 行。いずれも `echo "prod-entrypoint: ..."` 形式で、英語1行のあとに日本語の補足行が
  続く構造が多い

文言のスタイルは `images/devcontainer-base/bin/git-identity-setup` に揃える。`<コマンド名>: ` の
プレフィックス、小文字始まり、末尾ピリオドなし、複数の情報は `;` で連結、変数値は括弧で添える
（`(name=... email=...)`）形。

**意味は変えない。** 台帳が固定している「何を報告するか・何を伏せるか」はそのままで、言語だけを
移す。

### テストの追随

メッセージ本文を部分一致で検査している箇所を英語へ直す。

- `tests/karakuri-context.test.sh` 133 / 140 行 — `grep -qi "無い"`
- `tests/git-credential.test.sh` 603-605 / 633 / 653 行 — `grep -q "外れている"` と、その否定対照
  （`! grep -q "外れている"`）
- `tests/verify-docker.sh` 2317 / 2319 行 — `grep -q "生きている"` / `grep -q "外れている"`。
  実イメージ相手の E2E で、`pnpm test` では走らない（`pnpm verify:docker`）

**テストのラベル（ケース名として書かれている日本語）は変えない。** 台帳の索引がこの文字列を
引用しており、変えると台帳との対応が切れる。書き換えるのは検査対象の文字列だけである。

`images/runtime-base/README.md` 189-193 行が `karakuri-context` と `git-auth-check` の出力を
サンプルとして転記している。出荷物が出さなくなった文字列を公開面が持ち続けないよう、新しい文言へ
置き換える。

`tests/entrypoint.test.sh` は `prod-entrypoint.sh` の英語部分だけを見ているので追随は不要。
それでも書き換えで落ちないことを `pnpm test` で確かめる。

### 規約の新設

`docs/conventions.md` に節を1つ足す。内容は2点。

- **イメージに焼き込む出荷物が利用者へ出すメッセージは英語で書く。** 範囲は `images/*/bin`・
  `images/runtime-base/shims`・`packages/env-guard` の `bin` と `hooks`。これは
  `images/runtime-base/tests/shipped-symbols.test.sh` の lenient 検査が見ている範囲と同じである
- **コード内のコメントは日本語のままでよい。** 規約が縛るのは外へ出る文字列だけである

`images/runtime-base/templates/host` 配下（ホスト側ツールの usage を含む）が範囲の外であることも
書く。範囲の線は規約の一部なので明示する。ただしなぜ外なのかは書かない——判断の経緯は履歴層
（PR）に残す。

### やらないこと

- `templates/host` 配下の日本語は触らない。`karakuri.sh` / `prod-run.sh` / `dev-inject.sh` /
  `host-run.sh` の usage ヒアドキュメントに約70行あるが、別の変更として扱う
- コード内のコメントは触らない
- 日本語の混入を止める機械検査は置かない。規約の文だけで、押さえは人の目に委ねる
- `docs/guarantees.md` は編集しない。下記のとおり増減が無い

## 保証

### 新たに宣言する保証

- なし。台帳の §6 / §9 / §10 は3本の振る舞いだけを記述しており、メッセージ本文の字面を持たない
  （「鍵が無い旨の専用の1行が出る」のような書き方をしている）。文言の言語は台帳に現れず、
  規約の領分である

### 維持する保証

書き換える文言は、そのまま台帳が記述の対象にしているものである。壊れうる行を指す。

- §6（`images/runtime-base/tests/entrypoint.test.sh`）— 「解決できない旨を含むメッセージで非ゼロ
  終了する」「メッセージが脱出口の環境変数を名指しする」「取込失敗のメッセージは入力行そのものも
  鍵名そのものも出力に反射しない」「対象パスを名指しした警告を出したうえで続行する」。何を名指しし
  何を伏せるかは英訳後も同じでなければならない
- §9（`images/runtime-base/tests/karakuri-context.test.sh`）— 「鍵が無い旨の専用の1行が出る」
  「値は出力のどこにも現れない」、および「記録が無いときは何も言わないが、secret の置き場に
  ついては逆に『無い』と明示する」という意図的な非対称
- §10（`images/runtime-base/tests/git-credential.test.sh`）— 「常に1行を報告して 0 で終わる」
  「報告には実効ヘルパのパスが入り、イメージ固定の生死が実効ヘルパとは独立に入る」「報告文に
  トークンの値そのものは現れない」
- §11（`images/runtime-base/tests/shipped-symbols.test.sh`）— 英訳の過程で `§` や `D21` のような
  このリポジトリの外で解決できない記号を混ぜない。lenient 検査は `echo`/`printf` の行に記号が
  乗ることを許さない

### 廃止する保証

- なし。言語を移すだけで約束の取り下げではなく、台帳から消える行は無い
