# AIエージェント向けGit実行規則

最終更新: 2026-10-27

この文書は、AIエージェントがIssue、ブランチ、コミット、Pull Requestを扱うときの実行規則です。
運用の背景と人間の役割は [Git / GitHub運用方針](../git-workflow.md) を正典として参照し、ここでは
判断と操作の順序だけを定義します。

## まず読む

### Issueは仕様の正本であり、作成は実装開始の合図ではない

壁打ちで決まったことはその都度Issue本文へ反映し、最終的な仕様へ育てます。**壁打ちの結論を会話に
置き去りにしません。**仕様が整理され、人間が「この仕様で実装してよい」と判断して初めて、
ブランチ作成と実装へ進みます。

### Issue番号が指定されていない変更依頼

コードやドキュメントの変更を伴う依頼でIssue番号が指定されていない場合は、依頼内容から変更対象と
完了条件を整理し、既存Issueを検索します。なければ仕様検討フェーズに沿ってIssueを作り、
`実装可能` になってから「作業開始時の判断フロー」へ合流します。

例外は、typoやドキュメントの1行修正などについて、人間がその場でIssue不要と判断した場合に限ります。

### 本文とコメントの使い分け

Issue本文は**最新の仕様**だけを保ちます。検討の経緯（採用しなかった案と理由、判明した制約、
人間が下した判断）はコメントへ残します。

```powershell
gh issue comment <Issue番号> --body-file <本文ファイル>
```

### Issueの状態ラベル

| ラベル       | 意味                                             | 遷移させる主体                       |
| :----------- | :----------------------------------------------- | :----------------------------------- |
| `仕様検討中` | 壁打ち中。仕様が未確定のためAIは実装を開始しない | Issue作成時にAIが付ける              |
| `実装可能`   | 仕様確定済み。ブランチ作成と実装へ進んでよい     | **人間の指示を受けてAIが付け替える** |
| `実装中`     | 作業ブランチ作成済み。実装が進行中               | ブランチ作成時にAIが付け替える       |

```powershell
gh issue edit <Issue番号> --add-label "実装可能" --remove-label "仕様検討中"
gh issue edit <Issue番号> --add-label "実装中" --remove-label "実装可能"
```

**AIが独断で `実装可能` を付けることはしません。**次をすべて満たす場合に限り、根拠を示して遷移を
**提案**できます。

- 変更対象のファイルと箇所が特定できている
- 完了条件が一意に定まる
- 利用者への影響（フォルダ構成、`rules.json`、CSVの列）に判断の余地がない

## 詳細

### 作業開始時の判断フロー

人間から「Issue #12 の作業を開始して」と指示されたら、次の順序で進めます。

1. Issueを確認する（`gh issue view <番号>`）。`実装可能` でなければ停止して報告する。
2. 大枠Issueか子Issueかを確認する。子Issueなら本文の `Parent: #<番号>` から親ブランチを特定する。
3. 作業ツリーと現在ブランチを確認する（`git status`）。未コミットの変更があれば停止して報告する。
4. `core.hooksPath` を確認し、未設定なら `git config core.hooksPath .githooks` で有効にする。
5. 分岐元（大枠→`main`、子→親ブランチ）を `git fetch` で最新にし、そこから分岐する。
6. ブランチ名を `<Issue番号>-<type>/<内容>` で決めて作り、ラベルを `実装中` へ付け替える。
7. 実装し、意味のある単位で `<type>: <変更内容> #<Issue番号>` 形式でコミットする。
8. `scripts/verify.ps1` を実行し、差分を確認する。
9. Push前の報告を出し、そのままPushを実行して承認UIの承認を受ける。

### AIが実行してよい操作

- Issueの作成・本文更新・コメント・ラベル付け替え（`実装可能` への遷移を除く）
- 作業ブランチの作成、コミット、`git fetch`
- `scripts/verify.ps1`、`tests/run-tests.ps1`、`organize.ps1 -DryRun` の実行
- Pull Requestの内容と状態の確認

### 承認の受け取り方

#### 承認UIが使える環境

Push、Pull Request作成、作業ブランチの削除は、報告を出したうえで操作を実行し、そこで表示される
承認ダイアログへの承認を明示的な許可として扱います。会話で「許可をください」と言って停止しません。
プロジェクト設定（`.claude/settings.json`）でこれらは `ask` になっており、毎回確認されます。

#### 承認UIが使えない環境

報告を出したところで停止し、会話で明示的な許可を求めます。最終行は
`Pushは実行していません。内容を確認し、Pushの許可をください。` とします。

#### 承認UIのワンクリックで通さない操作

次の操作は承認UIの有無にかかわらず、実行前に会話で影響範囲を説明し、人間の判断を受けてから
進めます。

- Pull RequestのMerge（AIは実行しない）
- Force Push、公開済み履歴のrebase、`git reset --hard`
- `main` の削除、リポジトリ設定（Rulesets、ラベル定義、公開範囲）の変更
- 本物のダウンロードフォルダに対する `organize.ps1` の実行（`-DryRun` を除く）
- 大量ファイル削除など、既存作業を失う可能性のある操作

### Push前の報告テンプレート

AIは次をすべて埋めて報告し、続けてPushを実行します。

```markdown
## Push前の確認

- 現在のブランチ: `<branch>`
- 分岐元: `<base branch / commit>`
- Merge予定先: `<target branch>`
- 関連Issue: `#<番号> <タイトル>`
- Push予定: `<remote>/<branch>`
- 既存PRの状態: `<なし / #<番号> OPEN>`（`MERGED` なら**Pushせず**新ブランチへ切り出す）

### 作成したCommit

- `<hash> <件名>`

### 主な変更

- <変更内容>

### 変更規模

- 変更ファイル数: <件数>
- 追加 / 削除: <追加行数> / <削除行数>

### 品質確認

- `scripts/verify.ps1`: <pass / fail>
- 内訳（check:conflict-markers / check:ps1-syntax / check:ps1-bom / check:json / check:docs / check:hooks-lf / test）: <pass / fail>
- その他: <実フォルダでの -DryRun など>

### 既知の問題

- <なし / 内容>

ブランチ `<branch>` を `<remote>` へPushします。承認UIで確認してください。
```

### Pull Requestの作成

Push済みのブランチについて、PR案（Source / Target / 関連Issue / タイトル / 本文）を日本語で提示し、
続けて `gh pr create` を実行します。本文は [テンプレート](../../.github/pull_request_template.md) の
全項目を埋めます。Targetは分岐元（大枠→`main`、子→親ブランチ）です。

### Merge前のチェックリスト

AIはMergeを実行せず、次を確認して人間へ報告します。

- [ ] 対象Pull Requestの番号とURLが正しい
- [ ] Source branchが作業ブランチと一致する
- [ ] Target branchが分岐元と一致する
- [ ] 関連Issueと親子関係が正しい
- [ ] `scripts/verify.ps1` の実行結果がPull Requestに記録されている（CIが無いため、これが唯一の検証根拠）
- [ ] Conflictがない
- [ ] 大枠タスクから `main` の場合、[統合条件](../git-workflow.md#main-への統合条件) を満たしている

### Merge後の手順

`main` 宛てのPull Requestは `Closes #<番号>` でIssueが自動クローズされます。子タスク（親ブランチ宛て）は
自動クローズされないため、Mergeを確認してから手動でクローズします。

```powershell
gh pr view <PR番号> --json state,mergedAt
gh issue close <Issue番号> --comment "PR #<番号> がMergeされ、実装が完了したためクローズします。"
```

### ブランチ削除前のチェックリスト

Merge済みで不要になった作業ブランチは削除を提案します。`main` は削除対象にしません。

```powershell
# 1. Merge先に未マージのコミットがないこと（0以外なら削除しない）
git rev-list --count origin/main..origin/<branch>

# 2. Pull Requestが正常にMerge済みであること
gh pr list --state all --head <branch> --json number,state,title

# 3. 未MergeのPull Requestが残っていないこと
gh pr list --state open --head <branch>

# 4. 対象ブランチを分岐元とする子ブランチが存在しないこと
git branch -r --contains origin/<branch>
```

確認結果と削除予定のブランチ一覧を日本語で提示し、続けて削除を実行します（承認UIの承認を許可とみなす）。

```powershell
git push origin --delete <branch>
git branch -d <branch>
```

### コミット分割の判断基準

- 機能追加、バグ修正、リファクタ、テスト追加を、独立してレビューできる場合は別コミットにする。
- ドキュメントだけの変更とスクリプトの変更は、意図が独立していれば分ける。
- 構文エラーのある途中状態や、次のコミットがないと意味を持たない状態はコミットしない。

### このリポジトリ固有の確認

| 変更内容 | 追加確認 |
| --- | --- |
| `organize.ps1` の判定・移動 | `tests/run-tests.ps1` に対応するテストを追加し、実フォルダで `-DryRun` を確認する |
| `rules.example.json` の設定項目 | 既存の `rules.json` に項目がなくても動くこと（既定値）と、README の設定表を確認する |
| CSV の列 | 既存の CSV（旧形式・Shift-JIS）を読めることを確認する |
| `.ps1` の編集 | UTF-8（BOM 付き）で保存されていること（`check:ps1-bom`） |
