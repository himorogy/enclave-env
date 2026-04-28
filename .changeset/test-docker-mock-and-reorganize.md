---
"@himorogy/enclave-env": patch
---

テストを拡充・整理。

- `checkContainerNotRunning` / `checkDevContainerNotRunning` の全分岐を fake docker binary でテスト（コンテナ稼働・未稼働・docker 利用不可・DEVCONTAINER スキップ）
- `init-check-prod.sh` のテストを追加（同方式）
- TypeScript テストを `src/` から `tests/` に移動し、シェルテストと同一ディレクトリに集約
