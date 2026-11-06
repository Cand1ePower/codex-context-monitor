$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'Settings.ps1')
. (Join-Path $root 'Lifecycle.ps1')
foreach ($case in @(@('auto','zh-TW','zh-CN'),@('auto','en-GB','en-US'),@('auto','fr-FR','en-US'),@('en-US','zh-CN','en-US'))) {
 if ((Resolve-MonitorLanguage $case[0] $case[1]) -ne $case[2]) {throw 'Language selection failed'}
}
foreach ($case in @(@($true,$false,$false,'start'),@($false,$true,$false,'stop'),@($true,$true,$false,'wait'),@($true,$true,$true,'exit'))) {
 if ((Get-MonitorLifecycleAction $case[0] $case[1] $case[2]) -ne $case[3]) {throw 'Lifecycle transition failed'}
}
$zh=Get-Content -LiteralPath (Join-Path $root 'locales/zh-CN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$en=Get-Content -LiteralPath (Join-Path $root 'locales/en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (Compare-Object @($zh.PSObject.Properties.Name) @($en.PSObject.Properties.Name)) {throw 'Locale keys differ'}
foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.ps1')) {
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if ($errors) {throw ($file.Name+': '+($errors.Message -join '; '))}
}
Write-Output 'Language selection, lifecycle decisions, locale keys and PowerShell syntax passed.'
