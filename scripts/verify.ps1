# 品質ゲート。Pull Request の前に必ず実行し、結果を PR 本文へ記録する。
#   いずれかが失敗した時点で停止し、終了コード 1 を返す。
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $repo
try {
    $tracked = @(git ls-files) + @(git ls-files --others --exclude-standard) | Select-Object -Unique
    $ps1 = @($tracked | Where-Object { $_ -like '*.ps1' })

    $checks = [ordered]@{
        'check:conflict-markers' = {
            $hits = @(foreach ($f in $tracked) {
                if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
                Select-String -LiteralPath $f -Pattern '^(<{7}|={7}|>{7})( |$)' -Encoding UTF8 | ForEach-Object { "${f}:$($_.LineNumber)" }
            })
            if ($hits) { throw "衝突マーカーが残っています: $($hits -join ', ')" }
        }
        'check:ps1-syntax' = {
            foreach ($f in $ps1) {
                $errs = $null
                [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $f), [ref]$null, [ref]$errs)
                if ($errs) { throw "${f}: $($errs[0].Message)（$($errs[0].Extent.StartLineNumber) 行目）" }
            }
        }
        'check:ps1-bom' = {
            # Windows PowerShell 5.1 は BOM なし UTF-8 を正しく読めない
            $bad = @($ps1 | Where-Object {
                $b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $_))
                -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
            })
            if ($bad) { throw "UTF-8（BOM 付き）で保存されていません: $($bad -join ', ')" }
        }
        'check:json' = {
            foreach ($f in @($tracked | Where-Object { $_ -like '*.json' })) {
                try { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $f), [Text.Encoding]::UTF8) | ConvertFrom-Json | Out-Null }
                catch { throw "${f}: JSON として読めません" }
            }
        }
        'check:hooks-lf' = {
            $bad = @($tracked | Where-Object { $_ -like '.githooks/*' } | Where-Object {
                [IO.File]::ReadAllText((Resolve-Path -LiteralPath $_)).Contains("`r")
            })
            if ($bad) { throw "hook の改行が LF ではありません: $($bad -join ', ')" }
        }
        'test' = {
            & powershell.exe -NoProfile -File (Join-Path $repo 'tests\run-tests.ps1')
            if ($LASTEXITCODE -ne 0) { throw 'テストが失敗しました（上の出力を確認してください）' }
        }
    }

    foreach ($name in $checks.Keys) {
        try { & $checks[$name]; Write-Host "pass  $name" -ForegroundColor Green }
        catch { Write-Host "fail  $name" -ForegroundColor Red; Write-Host "      $($_.Exception.Message)"; exit 1 }
    }
    Write-Host 'すべての確認を通過しました。'
}
finally { Pop-Location }
