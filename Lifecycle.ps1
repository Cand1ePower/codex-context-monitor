function Get-MonitorLifecycleAction([bool]$codexPresent,[bool]$overlayRunning,[bool]$stopping) {
 if ($stopping) {return 'exit'}
 if ($codexPresent -and -not $overlayRunning) {return 'start'}
 if (-not $codexPresent -and $overlayRunning) {return 'stop'}
 return 'wait'
}
function Get-CodexWindowProcess {
 Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue |
  Where-Object {$_.MainWindowHandle -ne 0 -and $_.Path -match 'OpenAI[.\\].*Codex|OpenAI.Codex|[\\/]Codex[\\/]'} |
  Select-Object -First 1
}
