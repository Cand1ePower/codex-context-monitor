$ErrorActionPreference='Stop'
$runtime=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor'
$installDirectory=Join-Path $runtime 'app'
[void][IO.Directory]::CreateDirectory($runtime)
. (Join-Path $PSScriptRoot 'Settings.ps1')
$settings=Get-MonitorSettings
if (-not (Find-MonitorPython $settings)) {throw 'Python 3.10+ is required. Install Python, then run Install.ps1 again.'}
$old=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {$_.CommandLine -match 'CodexContextMonitor.*(?:Overlay|Watch-Codex)[.]ps1' -and $_.CommandLine -notmatch 'RenderPreview|ValidateOnly'})
& (Join-Path $PSScriptRoot 'Quit.ps1')
foreach ($item in $old) {
 $process=Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
 if ($process -and -not $process.WaitForExit(8000)) {throw 'The old monitor did not exit. Close it before installing.'}
}
[void][IO.Directory]::CreateDirectory($installDirectory)
$files=@('Overlay.ps1','Overlay.xaml','Settings.ps1','Watch-Codex.ps1','Launch.vbs','Quit.ps1','Uninstall.ps1','monitor.py','active_chat.py','billing.py','locales.json','pricing.json')
foreach ($name in $files) {
 $source=Join-Path $PSScriptRoot $name;$target=Join-Path $installDirectory $name
 if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) {Copy-Item -LiteralPath $source -Destination $target -Force}
}
$startupPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Context Monitor.vbs'
if ((Test-Path -LiteralPath $startupPath) -and (Get-Content -LiteralPath $startupPath -Raw) -notmatch 'CodexContextMonitor managed startup') {throw 'A different startup entry already uses this name.'}
$escaped=(Join-Path $installDirectory 'Launch.vbs').Replace('"','""')
$startup="' CodexContextMonitor managed startup`r`nCreateObject(""WScript.Shell"").Run ""wscript.exe "" & Chr(34) & ""$escaped"" & Chr(34), 0, False`r`n"
[IO.File]::WriteAllText($startupPath,$startup,[Text.Encoding]::Unicode)
Start-Process -FilePath 'wscript.exe' -ArgumentList ('"'+(Join-Path $installDirectory 'Launch.vbs')+'"') -WindowStyle Hidden
Write-Output ('Installed: '+$installDirectory)
Write-Output 'Automatic startup is enabled for this Windows user.'
