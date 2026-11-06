$ErrorActionPreference='Stop'
$runtime=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor'
[void][IO.Directory]::CreateDirectory($runtime)
. (Join-Path $PSScriptRoot 'Settings.ps1')
$created=$false
$watchMutex=New-Object Threading.Mutex($true,'Local\CodexContextMonitor-watcher-v1',[ref]$created)
if (-not $created) {$watchMutex.Dispose();exit 0}
$watchStop=Join-Path $runtime 'watcher-stop.request'
$overlayStop=Join-Path $runtime 'stop.request'
foreach ($path in @($watchStop,$overlayStop)) {if (Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path}}
$overlay=$null
try {
 while ($true) {
  $codexProcess=Get-CodexWindowProcess
  $alive=$null -ne $overlay -and -not $overlay.HasExited
  $action=Get-MonitorLifecycleAction ($null -ne $codexProcess) $alive (Test-Path -LiteralPath $watchStop)
  if ($action -eq 'exit') {break}
  if ($action -eq 'start') {
   $start=New-Object Diagnostics.ProcessStartInfo
   $start.FileName=Join-Path $PSHOME 'powershell.exe'
   $start.Arguments='-NoLogo -NoProfile -STA -WindowStyle Hidden -File "'+(Join-Path $PSScriptRoot 'Overlay.ps1')+'"'
   $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
   $overlay=[Diagnostics.Process]::Start($start)
  } elseif ($action -eq 'stop') {
   Set-Content -LiteralPath $overlayStop -Value 'stop' -Encoding ASCII
   [void]$overlay.WaitForExit(3000)
  }
  $state=@{watcher_pid=$PID;codex_pid=$(if ($codexProcess) {$codexProcess.Id} else {$null});overlay_pid=$(if ($overlay -and -not $overlay.HasExited) {$overlay.Id} else {$null});heartbeat_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
  $state | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $runtime 'watcher.json') -Encoding UTF8
  Start-Sleep -Seconds 2
 }
} catch {
 $_.Exception.Message | Set-Content -LiteralPath (Join-Path $runtime 'watcher-error.txt') -Encoding UTF8
} finally {
 if ($overlay -and -not $overlay.HasExited) {Set-Content -LiteralPath $overlayStop -Value 'stop' -Encoding ASCII;[void]$overlay.WaitForExit(3000)}
 $watchMutex.ReleaseMutex();$watchMutex.Dispose()
}
