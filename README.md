# @himorogy/enclave-env

**LLM に本番用秘密情報を渡さない**ための env 管理 CLI ツールです。

[dotenvx](https://dotenvx.com/) による暗号化と実行時ガードを組み合わせ、LLM が動く devcontainer から prod キーを構造的に隔離します。

## このパッケージが提供するもの

| 種別 | 内容 |
|---|---|
| **CLI** | `encrypt` / `decrypt` — env ファイルの暗号化・復号 |
| **CLI** | `check` — 平文 `.env*` のコミットをブロック（pre-commit hook 用） |
| **シェルスクリプト** | `scripts/init-check-dev.sh` — dev コンテナ起動時のセキュリティチェック（`initializeCommand` 用） |
| **シェルスクリプト** | `scripts/init-check-prod.sh` — prod コンテナ起動時の相互排他チェック（`initializeCommand` 用） |
| **テンプレート** | `templates/` — prod-shell スクリプト・devcontainer 構成の参照実装 |

**このパッケージが担わないもの：** devcontainer.json の作成・管理、prod 環境の構築。これらはプロジェクト側の責務です。テンプレートはその参照実装として提供します。

# セキュリティ思想

## なぜ必要か

Claude Code などの LLM は devcontainer 内から bind mount 経由でワークスペース全体にアクセスできます。`.env.production` または復号キーを平文で置いておくと、LLM が意図せず本番秘密情報を参照・出力するリスクがあります。
prod用復号キーをワークスペース外に置くことで devcontainer への同期を防ぎ、 `.env.production` が平文の状態で devcontainer に同期されないように複数層でブロックします。

`.env.production` に対する単一変数の追加・更新は下記の通り `dotenvx set` で対応できます。

```sh
dotenvx set DATABASE_URL "postgres://..." -f .env.production
```

- `.env.production` に含まれる public key だけで暗号化するため private key 不要
- 平文ファイルが一切ディスクに書き出されない
- dev コンテナ内でも実行可能（ただしコマンドヒストリーを削除しないと、LLMがセットした値を読み取ることが可能である点に留意）

## prod キー隔離の弊害

prod の private key を dev コンテナの外に置くと、dev コンテナ内から `.env.production` を復号できなくなります。
これは意図した動作ですが、複数変数を一覧で確認しながら編集したい場合や、prod deploy・DB メンテナンスを伴う作業には対応できません。そうしたワークフローのために prod 環境を用意します。

## 守るべき原則

prod 環境の実現手段は問いませんが、以下の 2 つを守ることがこのツールの前提です：

| 原則 | 目的 |
|---|---|
| **prod の private key は常にワークスペース外に置く** | bind mount 経由で LLM に渡らない |
| **prod 操作は dev コンテナが停止した状態で行う** | 復号した平文を LLM から守る |

---

# prod 環境の用意

## prod 環境の活用シナリオ

### 全復号して操作する

複数変数をまとめて確認・変更したい場合：

```sh
# 1. 復号
enclave-env decrypt --env prod

# 2. エディタで編集
vim .env.production

# 3. 再暗号化
enclave-env encrypt --env prod
```

`protected: true` の環境では、手順 1 が dev コンテナ稼働中にブロックされます。

### prod 環境の DB 整備や deploy

prod deploy・DB マイグレーションなど、prod の認証情報を使った操作も prod 環境内で完結できます。

```sh
pnpm deploy
pnpm db:migrate
```

## 運用上の注意点と 2 層の防御

全復号フロー中は `.env.production` が平文でディスクに存在します。この間に dev コンテナが起動すると、bind mount 経由で LLM が平文にアクセスできてしまいます。

enclave-env はこれを 2 つのレイヤーで防ぎます：

| レイヤー | タイミング | 担う側 | 実装 |
|---|---|---|---|
| 起動時 | devcontainer 起動 | **プロジェクト** が `initializeCommand` に登録 | `scripts/init-check-dev.sh` / `scripts/init-check-prod.sh` |
| 実行時 | `decrypt` 実行時 | **ライブラリ** が自動で実行 | `protected` フラグが付いた環境で dev コンテナの稼働を確認しブロック |

実行時ガードは `DEVCONTAINER=true`（コンテナ内からの実行）の場合はスキップされます。起動時ガードで保証済みのためです。

## 運用案

prod キーが使える実行環境の用意方法です。

### 選択肢 1：ホスト直実行

最もシンプル。dev コンテナを停止した状態でホストから実行します。

```sh
# DOTENV_PRIVATE_KEY_PRODUCTION が使える状態で
pnpm decrypt-env:prod
```

ホストに Node.js と `enclave-env` のインストールが必要です。

### 選択肢 2：prod-shell スクリプト（推奨）

Docker だけで prod 操作環境を再現するスクリプトを用意します。相互排他チェック・コンテナ起動・prod キー注入を 1 コマンドで行います。

```sh
sh scripts/prod-shell.sh
```

コンテナ内で `enclave-env`・`dotenvx`・各種デプロイツールが使えます。macOS / Linux 間の環境差が出ないため、CI/CD 安定前の prod deploy や DB メンテナンスも同じコンテナ内で完結します。

テンプレート：[`templates/prod-shell.sh`](./templates/prod-shell.sh)

### 選択肢 3：2 層 devcontainer

VS Code の「Reopen in Container」で prod devcontainer に切り替える構成です。再現性が最も高く、チームでの運用に向いています。

設計の核心は **Dockerfile を dev / prod で共有し、Claude Code のインストールを `dev/devcontainer.json` の `postCreateCommand` で行う**点です。同じ Dockerfile から prod 環境をビルドしても Claude Code が含まれない状態が構造的に保証されます。

```
.devcontainer/
├── Dockerfile        # 共有ベース（Claude Code なし）
├── dev/
│   └── devcontainer.json   # postCreateCommand で Claude Code をインストール
│                           # initializeCommand: init-check-dev.sh
└── prod/
    └── devcontainer.json   # Claude Code 関連の設定を含まない
                            # initializeCommand: init-check-prod.sh
```

テンプレート：[`templates/devcontainer/`](./templates/devcontainer/)

---

# インストール

```sh
pnpm add -D @himorogy/enclave-env @dotenvx/dotenvx simple-git-hooks
```

> `@dotenvx/dotenvx` は peer dependency です。プロジェクトに直接インストールしてください。

# セットアップ

## 1. `enclave-env` を作成する

プロジェクトルートに設定ファイルを置きます。シェルスクリプトから直接 `source` できる dotenv 形式です。

```sh
MODE=single

ENV_LOCAL_FILE=.env
ENV_PROD_FILE=.env.production
ENV_PROD_PROTECTED=true

DEV_CONTAINER_NAME=your-project-dev-devcontainer
PROD_CONTAINER_NAME=your-project-prod-devcontainer   # optional: prod-shell や 2層 devcontainer で使用
```

## 2. `package.json` にスクリプトと git hook を追加する

```json
{
  "scripts": {
    "decrypt-env":      "enclave-env decrypt --env local",
    "encrypt-env":      "enclave-env encrypt --env local",
    "decrypt-env:prod": "enclave-env decrypt --env prod",
    "encrypt-env:prod": "enclave-env encrypt --env prod",
    "prepare":          "simple-git-hooks"
  },
  "simple-git-hooks": {
    "pre-commit": "sh node_modules/@himorogy/enclave-env/scripts/check.sh"
  }
}
```

`pnpm install` 実行時に `prepare` が走り、フックが自動登録されます。

## 3. `.env` を dotenvx で暗号化する

```sh
pnpm encrypt-env
```

生成された `DOTENV_PUBLIC_KEY` はリポジトリにコミットします。`.env.keys` はコミットしないでください。

# CLI リファレンス

```
enclave-env encrypt --env <environment>   # 指定環境の env ファイルを in-place 暗号化
enclave-env decrypt --env <environment>   # 指定環境の env ファイルを in-place 復号
enclave-env check                         # ステージ済み .env* ファイルの暗号化確認（git pre-commit hook 用）
```

`<environment>` は `enclave-env` の `ENV_<NAME>_FILE` キーの `<NAME>` を小文字にしたものと一致させてください。

devcontainer の `initializeCommand` 用チェックはシェルスクリプトで提供しています：

```
scripts/init-check-dev.sh    # dev コンテナ起動時（enclave-env を source して実行）
scripts/init-check-prod.sh   # prod コンテナ起動時（enclave-env を source して実行）
```

# `enclave-env` 設定リファレンス

| キー | 説明 |
|---|---|
| `MODE` | `single` のみ実装済み |
| `ENV_<NAME>_FILE` | 環境 `<name>` の対象 env ファイルパス |
| `ENV_<NAME>_PROTECTED` | `true` の場合、`decrypt` 前に dev コンテナ稼働チェックを実行 |
| `DEV_CONTAINER_NAME` | `protected` チェックおよび `init-check-prod.sh` の対象コンテナ名 |
| `PROD_CONTAINER_NAME` | 設定すると 2 層 devcontainer モードで動作（`init-check-dev.sh` が起動チェックを実施） |

`<NAME>` は大文字・数字・アンダースコアで構成し、`--env` オプションでは小文字で参照します。例：`ENV_PROD_FILE` → `--env prod`

# キー管理の推奨構成

| 環境 | キーの保管場所 |
|---|---|
| local / dev | `.devcontainer/dev/.env.container`（gitignore 対象） |
| prod | `~/.config/<your-project>/.env.container`（ワークスペース外） |

prod キーをワークスペース外に置くことで、bind mount 経由で LLM に渡るリスクをなくします。

# Git 管理ポリシー（推奨）

| ファイル | Git 管理 |
|---|---|
| `.env`（local、暗号化済） | プロジェクトによる（未暗号化なら ❌ 推奨） |
| `.env.production`（暗号化済） | ✅ |
| `.env.keys*` | ❌ 必ず gitignore |
| `enclave-env` | ✅ |

# 機能一覧とテスト状況

| 機能 | 種別 | テスト |
|---|---|---|
| `enclave-env` ファイルの解析（`loadConfig`） | TypeScript | ✅ |
| env ファイルパスの解決（`resolveEnvFile`） | TypeScript | ✅ |
| ステージファイルの暗号化確認（`scripts/check.sh`） | シェル | ✅ |
| dev コンテナ起動時セキュリティチェック（`scripts/init-check-dev.sh`） | シェル | ✅ |
| prod コンテナ起動時相互排他チェック（`scripts/init-check-prod.sh`） | シェル | — |
| env ファイルの暗号化（`encrypt`） | TypeScript | — (dotenvx 依存) |
| env ファイルの復号（`decrypt`） | TypeScript | — (dotenvx 依存) |

```sh
pnpm test       # 全テスト
pnpm test:ts    # TypeScript のみ
pnpm test:sh    # シェルスクリプトのみ
```

# ライセンス

MIT
