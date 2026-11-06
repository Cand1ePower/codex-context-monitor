function Get-MonitorSettings {
 $settings=@{python=$null;language='auto'}
 foreach ($path in @((Join-Path $runtime 'settings.json'))) {
  if (Test-Path -LiteralPath $path) {
   try { $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in @('python','language')) {if ($null -ne $data.$key) {$settings[$key]=$data.$key}}
   } catch {}
  }
 }
 return $settings
}
function Find-MonitorPython($settings) {
 if ($settings.python -and (Test-Path -LiteralPath $settings.python)) {return $settings.python}
 foreach ($name in @('pythonw.exe','python.exe')) {
  $candidate=Get-Command $name -ErrorAction SilentlyContinue | Where-Object {$_.Source -notlike '*\Microsoft\WindowsApps\*'} | Select-Object -First 1
  if ($candidate) {return $candidate.Source}
 }
 $launcher=Get-Command py.exe -ErrorAction SilentlyContinue
 if ($launcher) {
  $candidate=(& $launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1)
  if ($candidate -and (Test-Path -LiteralPath $candidate)) {
   $windowless=Join-Path (Split-Path $candidate) 'pythonw.exe'
   if (Test-Path -LiteralPath $windowless) {return $windowless}
   return $candidate
  }
 }
 return $null
}
function Resolve-MonitorLanguage([string]$requested,[string]$systemLanguage) {
 if ($requested -and $requested -ne 'auto') {return $(if ($requested -like 'zh*') {'zh-CN'} else {'en-US'})}
 return $(if ($systemLanguage -like 'zh*') {'zh-CN'} else {'en-US'})
}

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
