# AGENTS.md

このファイルは、このリポジトリで作業するAIエージェント（Claude Code、Codex、Gemini など）共通の
ルールの単一ソースです。ツール固有の設定はそれぞれのファイル（`.claude/settings.json` など）に置き、
ルール本文はここへ書きます。

## プロジェクト概要

Windows のダウンロードフォルダを、`rules.json` のルールに従って振り分ける PowerShell スクリプトです。
利用者向けの説明は [README.md](README.md) にあります。

| パス | 役割 |
| --- | --- |
| `organize.ps1` | 本体。`-DryRun` で何も動かさずに結果だけ表示する |
| `install.ps1` | デスクトップにショートカットを作る |
| `rules.example.json` | 公開用のルールのひな形（自分用の `rules.json` は `.gitignore` 済み） |
| `scripts/verify.ps1` | 品質ゲート |
| `tests/run-tests.ps1` | 一時フォルダで整理を実行して結果を確かめるテスト |
| `.githooks/` | `main` への直接コミット・Pushを止めるhook |

## 必ず守ること

- 応答、Issue、コミット件名、Pull Request は日本語で書く。
- 作業の進め方は [Git / GitHub運用方針](docs/git-workflow.md) と
  [AIエージェント向けGit実行規則](docs/ai/git-operations.md) に従う。要点は次のとおり。
  - Issueは仕様の正本。`実装可能` になる前に実装を始めない。`実装可能` は人間だけが決める。
  - 作業ブランチは `<Issue番号>-<type>/<内容>`。大枠タスクは `main` から、子タスクは親ブランチから切る。
  - コミット件名は `<type>: <変更内容> #<Issue番号>`。
  - `main` へ直接コミット・Pushしない。Push・PR作成・ブランチ削除は報告してから実行し、承認UIで許可を受ける。
  - Pull RequestのMerge、Force Push、`git reset --hard`、リポジトリ設定の変更は行わない（人間に説明して判断を仰ぐ）。
- Push前に `scripts/verify.ps1` を実行し、結果をPush前の報告とPR本文へ記録する。ドキュメントだけの変更でも省略しない。
- 作業開始時に `git config core.hooksPath` を確認し、未設定なら `.githooks` を設定する。

## コードを書くときの注意

- 対象は Windows PowerShell 5.1。`?:`、`??`、`?.`、`&&`、`||` は使わない。
- `.ps1` は UTF-8（BOM 付き）・CRLF で保存する。BOM がないと日本語が文字化けして構文エラーになる。
- PowerShell の変数名は大文字・小文字を区別しない。`$R`（ルール）と `$r` のように、大文字小文字違いの変数を作らない。
- `rules.json` に新しい項目を足すときは、項目がない既存の `rules.json` でも動くよう既定値を持たせ、
  `rules.example.json` と README の設定表も更新する。
- 判定や移動の挙動を変えたら、`tests/run-tests.ps1` にテストを追加する。
- 本物のダウンロードフォルダ（`$env:USERPROFILE\Downloads`）に対して `organize.ps1` を `-DryRun` なしで実行しない。
- ファイルを削除する機能を足さない。捨てるものは削除候補へ移すのがこのツールの約束。
