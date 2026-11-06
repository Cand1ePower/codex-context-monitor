$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Quit.ps1')
$startupPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Context Monitor.vbs'
if ((Test-Path -LiteralPath $startupPath) -and (Get-Content -LiteralPath $startupPath -Raw) -match 'CodexContextMonitor managed startup') {Remove-Item -LiteralPath $startupPath}
Write-Output 'Automatic startup disabled; monitor stopped. App files and preferences are retained in LOCALAPPDATA/CodexContextMonitor.'
