# organize.ps1 の一連の動きを、一時フォルダの中だけで確かめるテスト。
#   本物のダウンロードフォルダや rules.json には触れない。
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$work = Join-Path ([IO.Path]::GetTempPath()) ("downloads-organizer-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$tool = Join-Path $work 'tool'
$dl = Join-Path $work 'dl'
$script:failures = @()

function Assert($cond, $message) {
    if ($cond) { Write-Host "  ok    $message" }
    else { Write-Host "  NG    $message" -ForegroundColor Red; $script:failures += $message }
}
function Exists($rel) { Test-Path -LiteralPath (Join-Path $dl $rel) }
function Put($rel, $content = 'x', [switch]$New) {
    $p = Join-Path $dl $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, $content)
    if (-not $New) { $old = (Get-Date).AddDays(-3); (Get-Item -LiteralPath $p).CreationTime = $old; (Get-Item -LiteralPath $p).LastWriteTime = $old }
}
function Organize([switch]$DryRun) {
    $argList = @('-NoProfile', '-File', (Join-Path $tool 'organize.ps1'), '-Root', $dl)
    if ($DryRun) { $argList += '-DryRun' }
    $out = & powershell.exe @argList 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "organize.ps1 が失敗しました:`n$out" }
    return $out
}
function Csv($rel) { [IO.File]::ReadAllText((Join-Path $dl $rel), [Text.Encoding]::UTF8) }

try {
    New-Item -ItemType Directory -Force -Path $tool, $dl | Out-Null
    # rules.json は置かず、初回実行で rules.example.json から作られることも確かめる
    Copy-Item -LiteralPath (Join-Path $repo 'organize.ps1'), (Join-Path $repo 'rules.example.json') -Destination $tool

    Put '2026 時間割.pdf'
    Put '講義メモ.pdf'
    Put 'setup.exe'
    Put 'a.zip' 'zip'; Put 'a\in.txt'
    Put 'b.pdf' 'same'; Put 'b (1).pdf' 'same'
    Put 'c.pdf' 'one'; Put 'c (1).pdf' 'two'
    Put 'weird.xyz'
    Put 'google-auth.json' '{}'
    Put 'Noto_Sans_JP.zip' 'font'
    Put 'Interview.pdf'
    Put '書類\report2.pdf' 'r2'; Put 'report2.pdf' 'r2'
    Put '書類\report3.pdf' 'old'; Put 'report3.pdf' 'new'
    Put '書類\入社承諾書_B.pdf' 'b'; Put '書類\入社承諾書_C.pdf' 'c'; Put '入社承諾書_A.pdf' 'a'
    Put 'fresh.pdf' -New
    Put 'x.crdownload'
    New-Item -ItemType Directory -Path (Join-Path $dl 'emptyDir') | Out-Null
    $old = (Get-Date).AddDays(-3); Get-Item -LiteralPath (Join-Path $dl 'a'), (Join-Path $dl 'emptyDir') | ForEach-Object { $_.CreationTime = $old; $_.LastWriteTime = $old }

    Write-Host 'お試し実行（-DryRun）'
    $out = Organize -DryRun
    Assert ($out -match 'お試し実行') 'お試し実行と表示される'
    Assert ((Exists '2026 時間割.pdf') -and -not (Exists '00_整理')) '何も移動しない'
    Assert (Test-Path -LiteralPath (Join-Path $tool 'rules.json')) 'rules.json が rules.example.json から作られる'

    Write-Host '1 回目'
    $out = Organize
    Assert (Exists '授業\2026 時間割.pdf') '強いキーワードで話題別フォルダへ'
    Assert (Exists '00_整理\要確認\講義メモ.pdf') '弱いキーワードだけなら要確認へ'
    Assert (Exists '00_整理\削除候補\setup.exe') 'インストーラーは削除候補へ'
    Assert (Exists '00_整理\削除候補\a.zip') '展開済みの zip は削除候補へ'
    Assert (Exists '00_整理\要確認\a\in.txt') '名前で判定できないフォルダは要確認へ'
    Assert ((Exists '00_整理\削除候補\b (1).pdf') -and (Exists '書類\b.pdf')) '中身が同じ (1) コピーは削除候補へ'
    Assert ((Exists '書類\c.pdf') -and (Exists '書類\c (1).pdf')) '中身が違う (1) は残す'
    Assert (Exists '00_整理\要確認\weird.xyz') '種類がわからないものは要確認へ'
    Assert (Exists '00_整理\要確認\google-auth.json') '機密情報らしいものは要確認へ'
    Assert (Exists 'フォント\Noto_Sans_JP.zip') 'フォント名の zip はフォントへ'
    Assert (Exists '書類\Interview.pdf') 'Inter で始まるだけの名前はフォントにしない'
    Assert (Exists '00_整理\削除候補\report2.pdf') '移動先に同じファイルがあれば削除候補へ'
    Assert ((Exists '書類\report3.pdf') -and (Exists '書類\report3 (2).pdf')) '移動先に別の同名ファイルがあれば番号を付ける'
    Assert ((Exists 'fresh.pdf') -and (Exists 'x.crdownload')) '新しいファイルとダウンロード中のファイルは動かさない'
    Assert (Exists '00_整理\削除候補\emptyDir') '空のフォルダは削除候補へ'
    Assert ((Csv '00_整理\要確認\_一覧.csv') -match '"講義メモ.pdf","弱いキーワード「講義」だけで判定","授業"') '要確認の一覧に理由と候補が載る'
    Assert ((Csv '00_整理\要確認\_新フォルダ提案.csv') -match '"入社承諾書","入社承諾書","3"') '共通する言葉から新フォルダを提案する'

    # 利用者の操作：Excel で Shift-JIS 保存された CSV に振り分け先と採用を書く
    $p = Join-Path $dl '00_整理\要確認\_一覧.csv'
    $c = (Csv '00_整理\要確認\_一覧.csv') -split "\r?\n" | Where-Object { $_ }
    $c = $c -replace '^("weird\.xyz",.*,)""$', '$1"その他"' -replace '^("講義メモ\.pdf",.*,)""$', '$1"削除候補"'
    [IO.File]::WriteAllLines($p, [string[]]$c, [Text.Encoding]::GetEncoding(932))
    $p = Join-Path $dl '00_整理\要確認\_新フォルダ提案.csv'
    $c = (Csv '00_整理\要確認\_新フォルダ提案.csv') -split "\r?\n" | Where-Object { $_ }
    $c = $c -replace '^"入社承諾書","入社承諾書",(.*),""$', '"就活","入社承諾書, 就活",$1,"○"'
    [IO.File]::WriteAllLines($p, [string[]]$c, (New-Object Text.UTF8Encoding $true))

    Write-Host '2 回目（CSV の指示を反映）'
    $out = Organize
    Assert (Exists 'その他\weird.xyz') '振り分け先に書いたフォルダへ移す（Shift-JIS の CSV も読める）'
    Assert (Exists '00_整理\削除候補\講義メモ.pdf') '振り分け先「削除候補」で削除候補へ移す'
    Assert ((Exists '就活\入社承諾書_A.pdf') -and (Exists '就活\入社承諾書_B.pdf') -and (Exists '就活\入社承諾書_C.pdf')) '採用した新フォルダへ、書類からも移す'
    $rules = [IO.File]::ReadAllText((Join-Path $tool 'rules.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert (@($rules.keywordCategories | Where-Object { $_.folder -eq '就活' }).Count -eq 1) '採用したフォルダが rules.json に追加される'

    Write-Host '3 回目（変化なし）'
    $out = Organize
    Assert ($out -match '移動するファイルはありませんでした') 'もう一度実行しても何も動かない'
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

if ($script:failures.Count) { Write-Host "$($script:failures.Count) 件失敗しました。" -ForegroundColor Red; exit 1 }
Write-Host 'すべてのテストに合格しました。'
