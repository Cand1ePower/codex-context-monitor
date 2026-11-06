$runtime = Join-Path $env:LOCALAPPDATA 'CodexContextMonitor'
if (Test-Path -LiteralPath $runtime) {
    Set-Content -LiteralPath (Join-Path $runtime 'stop.request') -Value 'stop' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $runtime 'watcher-stop.request') -Value 'stop' -Encoding ASCII
}
