# ダウンロードフォルダ整理スクリプト
#   ルールは同じフォルダの rules.json に書く（なければ rules.example.json から作る）。
#   自信のないものは要確認、捨ててよさそうなものは削除候補へ移す（削除はしない）。
param(
    [string]$Root = (Join-Path $env:USERPROFILE 'Downloads'),
    [switch]$DryRun,
    [switch]$Interactive
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rulesPath = Join-Path $here 'rules.json'
$logPath = Join-Path $here 'logs\移動ログ.csv'

$ReviewCols = 'ファイル名', '理由', '候補の行き先', '移動日', '振り分け先'
$TrashCols = 'ファイル名', '理由', 'サイズMB', '移動日'
$SuggestCols = '提案フォルダ', 'キーワード', '件数', '例', '採用'
$today = Get-Date -Format 'yyyy-MM-dd'

# ---------- 入出力 ----------
# Excel で保存し直すと Shift-JIS になることがあるので両対応
function Read-Text($path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    try { (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes).TrimStart([char]0xFEFF) }
    catch { [Text.Encoding]::GetEncoding(932).GetString($bytes) }
}
function Read-Csv($path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $lines = @((Read-Text $path) -split "\r?\n" | Where-Object { $_ })
    if ($lines.Count -lt 2) { return @() }
    @($lines | ConvertFrom-Csv)
}
function Write-Csv($rows, $path, $cols) {
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    $lines = @(($cols | ForEach-Object { '"' + $_ + '"' }) -join ',')
    if ($rows) { $lines = @($rows | Select-Object $cols | ConvertTo-Csv -NoTypeInformation) }
    try { [IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object Text.UTF8Encoding $true)) }
    catch { $script:warnings += "$(Split-Path $path -Leaf) に書き込めませんでした（Excel で開いていませんか？）" }
}
function Save-Rules {
    if ($DryRun) { return }
    [IO.File]::WriteAllText($rulesPath, ($R | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}

# ---------- 判定 ----------
function Has($name, $words) {
    foreach ($w in $words) { if ($w -and $name.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $w } }
    return $null
}
function Is-EmptyDir($p) { -not (Get-ChildItem -LiteralPath $p -Recurse -File -Force -EA SilentlyContinue | Select-Object -First 1) }
function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash }
function Normalize($n) { $n -replace '\s?\(\d+\)(?=\.[^.]+$|$)', '' }
function Decision($folder, $reason, $hint = '') { [pscustomobject]@{ Folder = $folder; Reason = $reason; Hint = $hint } }

function Classify($it) {
    $n = $it.Name
    if (($R.sensitiveExactNames -contains $n) -or (Has $n $R.sensitiveKeywords)) { return Decision $ReviewName '【注意】機密情報の可能性' }

    $fontPattern = '^(?:' + (($R.fontNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![a-z])'
    $isFontFile = (-not $it.PSIsContainer) -and ($R.fontExtensions -contains $it.Extension.ToLower())
    if ($isFontFile -or $n -match $fontPattern) { return Decision $R.fontFolder 'フォント' }

    $strong = @(); $weak = $null
    foreach ($c in $R.keywordCategories) {
        $w = Has $n $c.strong
        if ($w) { $strong += [pscustomobject]@{ Folder = $c.folder; Word = $w }; continue }
        if (-not $weak) { $w = Has $n $c.weak; if ($w) { $weak = [pscustomobject]@{ Folder = $c.folder; Word = $w } } }
    }
    $folders = @($strong | ForEach-Object { $_.Folder } | Select-Object -Unique)
    if ($folders.Count -eq 1) { return Decision $folders[0] "キーワード「$($strong[0].Word)」" }
    if ($folders.Count -gt 1) { return Decision $ReviewName '複数のフォルダに該当' ($folders -join '／') }
    if ($weak) { return Decision $ReviewName "弱いキーワード「$($weak.Word)」だけで判定" $weak.Folder }

    if ($it.PSIsContainer) { return Decision $ReviewName 'フォルダ（名前から判定できない）' }
    $e = $it.Extension.ToLower()
    foreach ($c in $R.extensionCategories) { if ($c.extensions -contains $e) { return Decision $c.folder "拡張子 $e" } }
    if (-not $e) { $e = '拡張子なし' }
    return Decision $ReviewName "判定できない種類（$e）"
}

# ---------- 移動 ----------
function Unique-Path($dir, $it) {
    $base = $it.Name; $ext = ''
    if (-not $it.PSIsContainer) { $base = [IO.Path]::GetFileNameWithoutExtension($it.Name); $ext = $it.Extension }
    for ($i = 2; ; $i++) { $p = Join-Path $dir "$base ($i)$ext"; if (-not (Test-Path -LiteralPath $p)) { return $p } }
}
function Move-To($it, $folder, $reason, $hint = '') {
    $dir = Join-Path $Root $folder
    $dest = Join-Path $dir $it.Name
    if (Test-Path -LiteralPath $dest) {
        $other = Get-Item -LiteralPath $dest -Force
        if ($folder -ne $TrashName -and -not $it.PSIsContainer -and -not $other.PSIsContainer -and (Hash $it.FullName) -eq (Hash $dest)) {
            return Move-To $it $TrashName "「$folder」に同じファイルあり"
        }
        $dest = Unique-Path $dir $it
    }
    $size = $it.Length
    if ($it.PSIsContainer) { $size = (Get-ChildItem -LiteralPath $it.FullName -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Move-Item -LiteralPath $it.FullName -Destination $dest
        if (-not (Test-Path -LiteralPath $logPath)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null
            [IO.File]::WriteAllText($logPath, "日時,元,先,理由`r`n", (New-Object Text.UTF8Encoding $true))
        }
        $line = (@((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $it.FullName, $dest, $reason) | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ','
        [IO.File]::AppendAllText($logPath, $line + "`r`n", (New-Object Text.UTF8Encoding $false))
    }
    $m = [pscustomobject]@{ Name = (Split-Path $dest -Leaf); Folder = $folder; Reason = $reason; Hint = $hint; MB = [math]::Round($size / 1MB, 1) }
    $script:moves += $m
    return $m
}

# ---------- 本体 ----------
$moves = @(); $warnings = @(); $skippedNew = 0
if (-not (Test-Path -LiteralPath $rulesPath)) { Copy-Item -LiteralPath (Join-Path $here 'rules.example.json') -Destination $rulesPath }
$R = Read-Text $rulesPath | ConvertFrom-Json

# 要確認・削除候補の場所（ダウンロードからの相対パス。下の階層にも置ける）
$ReviewName = '00_整理\要確認'; if ($R.reviewFolder) { $ReviewName = $R.reviewFolder.Trim('\') }
$TrashName = '00_整理\削除候補'; if ($R.trashFolder) { $TrashName = $R.trashFolder.Trim('\') }
$ReviewDir = Join-Path $Root $ReviewName
$TrashDir = Join-Path $Root $TrashName
$ReviewCsv = Join-Path $ReviewDir '_一覧.csv'
$TrashCsv = Join-Path $TrashDir '_一覧.csv'
$SuggestCsv = Join-Path $ReviewDir '_新フォルダ提案.csv'

# 1. 新フォルダ提案のうち「採用」に印があるものをルールへ追加
$adopted = @()
foreach ($s in (Read-Csv $SuggestCsv)) {
    if (-not "$($s.採用)".Trim()) { continue }
    $folder = "$($s.提案フォルダ)".Trim()
    $kw = @("$($s.キーワード)" -split '[,、，]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $folder -or -not $kw) { continue }
    $cat = $R.keywordCategories | Where-Object { $_.folder -eq $folder } | Select-Object -First 1
    if ($cat) { $cat.strong = @(@($cat.strong) + $kw | Select-Object -Unique) }
    else { $R.keywordCategories += [pscustomobject]@{ folder = $folder; strong = $kw; weak = @() } }
    $adopted += $folder
}
$managed = @(($ReviewName -split '\\')[0], ($TrashName -split '\\')[0], $R.fontFolder) + @($R.otherFolders) +
    @($R.keywordCategories | ForEach-Object { $_.folder }) + @($R.extensionCategories | ForEach-Object { $_.folder })
# 拡張子だけで振り分けた「書類」「画像」などは、話題別フォルダの提案元・移動元になる
$typeDirs = @($R.extensionCategories | ForEach-Object { Join-Path $Root $_.folder } | Where-Object { Test-Path -LiteralPath $_ })

if ($adopted) {
    Save-Rules
    foreach ($dir in $typeDirs) {
        foreach ($it in @(Get-ChildItem -LiteralPath $dir -File -Force)) {
            $d = Classify $it
            if ($adopted -contains $d.Folder) { Move-To $it $d.Folder "$($d.Reason)（新フォルダ採用）" | Out-Null }
        }
    }
}

# 2. 要確認：「振り分け先」が書かれたものを移動し、残りはルールで判定し直す
$reviewRows = @{}
foreach ($csvRow in (Read-Csv $ReviewCsv)) { $reviewRows[$csvRow.ファイル名] = $csvRow }
if (Test-Path -LiteralPath $ReviewDir) {
    foreach ($it in @(Get-ChildItem -LiteralPath $ReviewDir -Force | Where-Object { -not $_.Name.StartsWith('_') })) {
        $row = $reviewRows[$it.Name]
        $target = ''
        if ($row) { $target = "$($row.振り分け先)".Trim().Trim('\') }
        if ($target -and $target -notmatch '\.\.') {
            if ($target -in '削除', '削除候補', $TrashName, (Split-Path $TrashName -Leaf)) { $target = $TrashName }
            $top = ($target -split '\\')[0]
            if ($managed -notcontains $top) { $R.otherFolders = @(@($R.otherFolders) + $top); $managed += $top; Save-Rules }
            Move-To $it $target '手動で振り分け' | Out-Null
            $reviewRows.Remove($it.Name)
            continue
        }
        $d = Classify $it
        if ($d.Folder -ne $ReviewName) { Move-To $it $d.Folder "$($d.Reason)（要確認から再判定）" | Out-Null; $reviewRows.Remove($it.Name); continue }
        if (-not $row) { $reviewRows[$it.Name] = [pscustomobject]@{ ファイル名 = $it.Name; 理由 = $d.Reason; 候補の行き先 = $d.Hint; 移動日 = $today; 振り分け先 = '' } }
    }
}

# 3. ダウンロード直下を判定
$items = @(Get-ChildItem -LiteralPath $Root -Force | Where-Object {
    ($managed -notcontains $_.Name) -and ($R.skipNames -notcontains $_.Name) -and -not $_.Name.StartsWith('~$')
})
$cutoff = (Get-Date).AddHours(-[double]$R.minAgeHours)

# 中身が同じ「(1)」付きコピーを先に洗い出す
$dupOf = @{}
$items | Where-Object { -not $_.PSIsContainer } | Group-Object { Normalize $_.Name } | Where-Object Count -gt 1 | ForEach-Object {
    $sorted = @($_.Group | Sort-Object { if ($_.Name -eq (Normalize $_.Name)) { 0 } else { 1 } }, { $_.Name.Length }, Name)
    $keep = $sorted[0]
    foreach ($o in $sorted[1..($sorted.Count - 1)]) {
        if ($o.Length -eq $keep.Length -and (Hash $o.FullName) -eq (Hash $keep.FullName)) { $dupOf[$o.FullName] = $keep.Name }
    }
}

# 同名フォルダが先に移動されても判定が変わらないよう、移動前に調べておく
$extractedZips = @{}
foreach ($it in $items | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.zip' }) {
    $sib = Join-Path $Root $it.BaseName
    if ((Test-Path -LiteralPath $sib -PathType Container) -and -not (Is-EmptyDir $sib)) { $extractedZips[$it.FullName] = $true }
}

foreach ($it in $items) {
    if (-not $it.PSIsContainer -and $R.inProgressExtensions -contains $it.Extension.ToLower()) { $skippedNew++; continue }
    $newest = $it.LastWriteTime; if ($it.CreationTime -gt $newest) { $newest = $it.CreationTime }
    if ($newest -gt $cutoff) { $skippedNew++; continue }

    $trash = $null
    if (-not $it.PSIsContainer) {
        $e = $it.Extension.ToLower()
        if ($R.deleteCandidateExtensions -contains $e) { $trash = 'インストーラー' }
        elseif ($dupOf.ContainsKey($it.FullName)) { $trash = "「$($dupOf[$it.FullName])」と同じ中身のコピー" }
        elseif ($extractedZips[$it.FullName]) { $trash = '展開済みの zip（同名フォルダあり）' }
    }
    elseif (Is-EmptyDir $it.FullName) { $trash = '空のフォルダ' }

    if ($trash) { Move-To $it $TrashName $trash | Out-Null; continue }
    $d = Classify $it
    Move-To $it $d.Folder $d.Reason $d.Hint | Out-Null
}

# 4. 一覧ファイルを更新
foreach ($m in $moves | Where-Object Folder -eq $ReviewName) {
    $reviewRows[$m.Name] = [pscustomobject]@{ ファイル名 = $m.Name; 理由 = $m.Reason; 候補の行き先 = $m.Hint; 移動日 = $today; 振り分け先 = '' }
}
if ($reviewRows.Count -or (Test-Path -LiteralPath $ReviewCsv)) { Write-Csv @($reviewRows.Values | Sort-Object 移動日, ファイル名) $ReviewCsv $ReviewCols }

$trashRows = @(Read-Csv $TrashCsv | Where-Object { Test-Path -LiteralPath (Join-Path $TrashDir $_.ファイル名) })
foreach ($m in $moves | Where-Object Folder -eq $TrashName) {
    $trashRows += [pscustomobject]@{ ファイル名 = $m.Name; 理由 = $m.Reason; サイズMB = $m.MB; 移動日 = $today }
}
if ($trashRows.Count -or (Test-Path -LiteralPath $TrashCsv)) { Write-Csv $trashRows $TrashCsv $TrashCols }

# 5. 要確認と種類別フォルダのファイル名から、新しいフォルダの候補を探す
$known = @($R.keywordCategories | ForEach-Object { @($_.strong) + @($_.weak) }) + $managed
$names = @($reviewRows.Keys)
foreach ($dir in $typeDirs) { $names += @(Get-ChildItem -LiteralPath $dir -File -Force -Name) }
if ($DryRun) { $names += @($moves | Where-Object { $R.extensionCategories.folder -contains $_.Folder } | ForEach-Object { $_.Name }) }
$tokenFiles = @{}; $tokenLabel = @{}
foreach ($name in $names) {
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $seen = @{}
    foreach ($m in [regex]::Matches($base, '\p{IsCJKUnifiedIdeographs}{2,}|\p{IsKatakana}{2,}|[A-Za-z]{3,}')) {
        $t = $m.Value; $k = $t.ToLower()
        if ($seen[$k] -or $R.stopwords -contains $t -or (Has $t $known)) { continue }
        $seen[$k] = $true
        if (-not $tokenFiles[$k]) { $tokenFiles[$k] = @(); $tokenLabel[$k] = $t }
        $tokenFiles[$k] += $name
    }
}
$suggestions = @($tokenFiles.Keys | Where-Object { $tokenFiles[$_].Count -ge [int]$R.suggestMinFiles } |
    Sort-Object { -$tokenFiles[$_].Count }, { $_ } | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{ 提案フォルダ = $tokenLabel[$_]; キーワード = $tokenLabel[$_]; 件数 = $tokenFiles[$_].Count
            例 = (@($tokenFiles[$_] | Select-Object -First 3) -join ' / '); 採用 = '' }
    })
if ($suggestions.Count -or (Test-Path -LiteralPath $SuggestCsv)) { Write-Csv $suggestions $SuggestCsv $SuggestCols }

# 6. 結果
$stale = @($trashRows | Where-Object { $_.移動日 -and ([datetime]$_.移動日) -lt (Get-Date).AddDays(-[double]$R.staleDays) })
$staleMB = [math]::Round(($stale | ForEach-Object { [double]$_.サイズMB } | Measure-Object -Sum).Sum)

$lines = @()
if ($DryRun) { $lines += '【お試し実行：実際には動かしていません】' }
if ($moves.Count) { $lines += "移動：$($moves.Count) 件"; $moves | Group-Object Folder | Sort-Object Name | ForEach-Object { $lines += "  $($_.Name)：$($_.Count) 件" } }
else { $lines += '移動するファイルはありませんでした。' }
if ($skippedNew) { $lines += "新しいファイル $skippedNew 件は次回に回しました（$($R.minAgeHours) 時間以内・ダウンロード中）。" }
if ($adopted) { $lines += "新しいフォルダをルールに追加：$($adopted -join '、')" }
if ($reviewRows.Count) { $lines += "要確認に $($reviewRows.Count) 件あります。" }
if ($suggestions.Count) { $lines += "新フォルダの提案が $($suggestions.Count) 件あります（$ReviewName\_新フォルダ提案.csv）。" }
if ($stale.Count) { $lines += "削除候補に $($R.staleDays) 日以上置いてあるもの：$($stale.Count) 件／約 $staleMB MB" }
$lines += $warnings
$summary = $lines -join "`r`n"
$summary
if ($DryRun) {
    ''; '--- 詳細'; $moves | ForEach-Object { "[$($_.Folder)] $($_.Name)  ← $($_.Reason)" }
    if ($suggestions.Count) { ''; '--- 新フォルダの提案'; $suggestions | ForEach-Object { "$($_.提案フォルダ)（$($_.件数) 件）例：$($_.例)" } }
}

if ($Interactive) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($summary, 'ダウンロード整理')
    if ($moves | Where-Object Folder -eq $ReviewName) { Start-Process explorer.exe $ReviewDir }
    if ($moves | Where-Object Folder -eq $TrashName) { Start-Process explorer.exe $TrashDir }
}
