# デスクトップに「ダウンロード整理」ショートカットを作る（-Uninstall で削除）
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ダウンロード整理.lnk'

if ($Uninstall) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk; 'ショートカットを削除しました。' }
    else { 'ショートカットはありません。' }
    return
}

$rules = Join-Path $here 'rules.json'
if (-not (Test-Path -LiteralPath $rules)) {
    Copy-Item -LiteralPath (Join-Path $here 'rules.example.json') -Destination $rules
    'rules.json を作成しました（rules.example.json のコピー）。'
}

$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$s.Arguments = "-NoProfile -WindowStyle Minimized -File `"$(Join-Path $here 'organize.ps1')`" -Interactive"
$s.WorkingDirectory = $here
$s.IconLocation = Join-Path $env:SystemRoot 'System32\shell32.dll,46'
$s.Description = 'ダウンロードフォルダを整理'
$s.Save()
"ショートカットを作成しました：$lnk"
