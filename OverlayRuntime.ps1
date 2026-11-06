# Loaded by Overlay.ps1 after the native helper and XAML have been created.
$createdNew = $false
$mutexName = if ($RenderPreview) {'Local\CodexContextMonitor-preview-' + $PID} else {'Local\CodexContextMonitor-v1'}
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); exit 0 }
$stopPath = Join-Path $runtime 'stop.request'
if (-not $RenderPreview -and (Test-Path -LiteralPath $stopPath)) { Remove-Item -LiteralPath $stopPath }
$script:placement = @{leftRatio=0.46;bottom=24.0}
$placementPath = Join-Path $runtime 'placement.json'
if (Test-Path -LiteralPath $placementPath) {
 try {
  $saved = Get-Content -LiteralPath $placementPath -Raw | ConvertFrom-Json
  $script:placement.leftRatio = [math]::Max(0,[math]::Min(1,[double]$saved.leftRatio))
  $script:placement.bottom = [math]::Max(0,[double]$saved.bottom)
 } catch {}
}
$script:dragging = $false
$script:closed = $false
$script:ownerHandle = [IntPtr]::Zero
$script:ownerPid = 0
$script:ownerBounds = $null
$script:lastState = $null
$script:lastStateWrite = [datetime]::MinValue
$script:nextOwnerScan = [datetime]::MinValue
$script:nextOwnerWrite = [datetime]::MinValue
$script:forceVisibleUntil = [datetime]::MinValue
$script:popupClosedAt = [datetime]::MinValue
$script:modelSignature = ''
$script:worker = $null
$script:compactWidth = 254.0
$script:compactHeight = 26.0

function Set-Expanded([bool]$value) {
 $ui.DetailsPopup.IsOpen = $value
 if ($value) { Follow-Owner }
}
function Format-Tokens($number) {
 if ($null -eq $number) { return '—' }
 if ($number -ge 1000000) { return ('{0:0.00}M' -f ($number/1000000.0)) }
 if ($number -ge 1000) { return ('{0:0.0}K' -f ($number/1000.0)) }
 return ('{0:0}' -f $number)
}
function Format-Cost($number) {
 if ($null -eq $number) { return (L 'Unpriced') }
 if ($number -gt 0 -and $number -lt 0.01) { return ('$' + ('{0:0.0000}' -f $number)) }
 return ('$' + ('{0:0.00}' -f $number))
}
function Set-Usage($data) {
 $script:lastState = $data
 $ready = $data.history_complete -ne $false
 $ui.ExpandButton.ToolTip = (L 'CurrentChat') -f $data.title
 if ($null -ne $data.percent -and $ready) {
  $ui.PercentLarge.Text = '{0:0.0}%' -f $data.percent
  $ring.Percent = [double]$data.percent
  $ui.UsageText.Text = (Format-Tokens $data.usage.total_tokens) + ' / ' + (Format-Tokens $data.window)
 } else {
  $ui.PercentLarge.Text = '—'; $ring.Percent = [double]::NaN
  $ui.UsageText.Text = if (-not $ready) {L 'Indexing'} elseif ($data.error) {if (-not $data.thread_id) {L 'NoChat'} else {L 'Waiting'}} elseif ($data.compacted) {L 'Compacted'} else {L 'Waiting'}
 }
 $cache = if ($null -ne $data.cache_percent -and $ready) {'{0:0.0}%' -f $data.cache_percent} else {'—'}
 $speed = if ($null -ne $data.speed_tps -and $ready) {'≈ ' + ('{0:0.0}' -f $data.speed_tps) + ' t/s'} else {'— t/s'}
 $ui.CacheSmall.Text = (L 'CacheHitRate') + ' ' + $cache; $ui.CacheLarge.Text = (L 'CacheHitRate') + ' ' + $cache
 $ui.SpeedSmall.Text = $speed; $ui.SpeedLarge.Text = $speed
 $ui.CachedValue.Text = Format-Tokens $data.usage.cached_input_tokens
 $ui.NewValue.Text = if ($null -ne $data.usage) {Format-Tokens ($data.usage.input_tokens-$data.usage.cached_input_tokens)} else {'—'}
 $ui.OutputValue.Text = Format-Tokens $data.usage.output_tokens
 $ui.RemainingValue.Text = Format-Tokens $data.remaining
 $segments = @($ui.CachedSegment,$ui.NewSegment,$ui.OutputSegment)
 $values = if ($null -ne $data.usage -and $ready) {@($data.usage.cached_input_tokens,($data.usage.input_tokens-$data.usage.cached_input_tokens),$data.usage.output_tokens)} else {@(0,0,0)}
 $denominator = if ($data.window) {[math]::Max([double]$data.window,[double]$data.usage.total_tokens)} else {0}
 for ($index=0; $index -lt 3; $index++) { $segments[$index].Width = if ($denominator -gt 0) {310.0*$values[$index]/$denominator} else {0} }
 $bill = $data.billing
 $signature = $bill | ConvertTo-Json -Depth 8 -Compress
 if ($signature -ne $script:modelSignature) {
  $rows = @($bill.models | ForEach-Object {
   if ($null -ne $_) {
    $tip = (L 'ModelHelp') -f $_.model,('{0:N0}' -f $_.input_tokens),('{0:N0}' -f $_.cached_input_tokens),('{0:N0}' -f $_.output_tokens),('{0:N0}' -f $_.total_tokens),$_.requests
    $name=if ($_.model -eq 'unknown') {L 'UnknownModel'} else {$_.display_name}
    [pscustomobject]@{name=$name;tokens=(Format-Tokens $_.total_tokens);cost=(Format-Cost $_.cost_usd);tooltip=$tip}
   }
  })
  $ui.ModelsList.ItemsSource = $rows
  $ui.EmptyModels.Visibility = if ($rows.Count) {'Collapsed'} else {'Visible'}
  $script:modelSignature = $signature
 }
 $ui.PriceLabel.Text = if ($bill.partial) {L 'PartialEstimate'} else {L 'Estimate'}
 $ui.TotalCost.Text = if (-not $ready) {L 'Calculating'} elseif (-not $bill.requests) {'—'} elseif ($bill.partial) {'≥ ' + (Format-Cost $bill.known_cost_usd)} else {'≈ ' + (Format-Cost $bill.cost_usd)}
 $ui.PriceSource.ToolTip = (L 'EstimateHelp') -f $bill.pricing_date
 $ui.TotalCost.ToolTip = $ui.PriceSource.ToolTip
 Update-Age
}
function Update-Age {
 if ($RenderPreview) {return}
 $data = $script:lastState
 if ($null -eq $data) { return }
 if (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$data.heartbeat_ms) -gt 6000) {
  $ui.UsageText.Text = L 'Interrupted'
  $ui.ExpandButton.ToolTip = L 'Stale'
 }
}
function Follow-Owner {
 if ($script:dragging -or $script:closed) { return }
 $now = [datetime]::UtcNow
 $foreground = [ContextMeter.Native]::GetForegroundWindow()
 [uint32]$foregroundPid = 0
 [void][ContextMeter.Native]::GetWindowThreadProcessId($foreground,[ref]$foregroundPid)
 $candidate = $null
 if ($foregroundPid -ne $PID -and $foregroundPid -gt 0 -and $foreground -ne $script:ownerHandle) {
  $candidate = Get-Process -Id $foregroundPid -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -eq 'ChatGPT' -and $_.Path -match 'OpenAI[.\\].*Codex|OpenAI.Codex'}
 }
 if ($null -ne $candidate) {
  $script:ownerHandle = [ContextMeter.Native]::GetAncestor($foreground,2)
  $script:ownerPid = $candidate.Id
 } elseif ($now -gt $script:nextOwnerScan -or -not [ContextMeter.Native]::IsWindow($script:ownerHandle)) {
  $script:nextOwnerScan = $now.AddSeconds(3)
  $process = Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.Path -match 'OpenAI[.\\].*Codex|OpenAI.Codex'} | Select-Object -First 1
  if ($null -ne $process -and -not [ContextMeter.Native]::IsWindow($script:ownerHandle)) { $script:ownerHandle=$process.MainWindowHandle; $script:ownerPid=$process.Id }
 }
 if ($script:ownerHandle -ne [IntPtr]::Zero) {
  $helper = New-Object Windows.Interop.WindowInteropHelper $window
  if ($helper.Owner -ne $script:ownerHandle) { $helper.Owner=$script:ownerHandle }
 }
 if ($now -gt $script:nextOwnerWrite) {
  @{process_id=$script:ownerPid;window_handle=$script:ownerHandle.ToInt64();heartbeat_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()} | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $runtime 'owner.json') -Encoding UTF8
  $script:nextOwnerWrite=$now.AddSeconds(1)
 }
 if ($script:ownerHandle -eq [IntPtr]::Zero -or -not [ContextMeter.Native]::IsWindow($script:ownerHandle) -or [ContextMeter.Native]::IsIconic($script:ownerHandle)) {
  if ($now -gt $script:forceVisibleUntil) {$ui.DetailsPopup.IsOpen=$false;$window.Hide();return}
 }
 if ($foreground -ne $script:ownerHandle -and $foregroundPid -ne $PID -and $now -gt $script:forceVisibleUntil) {
  $ui.DetailsPopup.IsOpen=$false;$window.Hide();return
 }
 $rect = New-Object ContextMeter.Native+RECT
 if ([ContextMeter.Native]::GetWindowRect($script:ownerHandle,[ref]$rect)) {
  $source = [Windows.PresentationSource]::FromVisual($window)
  $sx=if ($null -ne $source) {$source.CompositionTarget.TransformToDevice.M11} else {1.0}
  $sy=if ($null -ne $source) {$source.CompositionTarget.TransformToDevice.M22} else {1.0}
  $bounds=@{left=$rect.Left/$sx;top=$rect.Top/$sy;right=$rect.Right/$sx;bottom=$rect.Bottom/$sy}
  $script:ownerBounds=$bounds
  $oldLeft=$window.Left;$oldTop=$window.Top
  $window.Left=$bounds.left+[math]::Max(0,($bounds.right-$bounds.left-$script:compactWidth))*$script:placement.leftRatio
  $window.Top=[math]::Max($bounds.top+40,$bounds.bottom-$script:placement.bottom-$script:compactHeight)
  if ($ui.DetailsPopup.IsOpen -and ($oldLeft -ne $window.Left -or $oldTop -ne $window.Top)) {
   $ui.DetailsPopup.HorizontalOffset=-93.99;$ui.DetailsPopup.HorizontalOffset=-94
  }
 }
 if (-not $window.IsVisible) {$window.Show()}
}

if ($RenderPreview) {
 $previewData=Get-Content -LiteralPath $PreviewState -Raw -Encoding UTF8 | ConvertFrom-Json
 Set-Usage $previewData
 [void][IO.Directory]::CreateDirectory($PreviewOutput)
 foreach ($mode in @('collapsed','expanded')) {
  $root=if ($mode -eq 'expanded') {$ui.Details} else {$ui.Bar}
  $width=if ($mode -eq 'expanded') {348} else {254}
  $root.Measure((New-Object Windows.Size($width,[double]::PositiveInfinity)))
  $height=[math]::Ceiling($root.DesiredSize.Height)
  $root.Arrange((New-Object Windows.Rect(0,0,$width,$height)));$root.UpdateLayout()
  $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(([int]($width*1.5)),([int]($height*1.5)),144,144,([Windows.Media.PixelFormats]::Pbgra32))
  $bitmap.Render($root)
  $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
  $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $stream=[IO.File]::Create((Join-Path $PreviewOutput ('preview-'+$mode+'.png')))
  try {$encoder.Save($stream)} finally {$stream.Dispose()}
 }
 @{percent=$ui.PercentLarge.Text;modelRows=$ui.ModelsList.Items.Count;cost=$ui.TotalCost.Text;panelHeight=$ui.Details.ActualHeight;outsideClickCloses=(-not $ui.DetailsPopup.StaysOpen)} | ConvertTo-Json -Compress
 $mutex.ReleaseMutex();$mutex.Dispose();exit 0
}

$ui.ExpandButton.Add_Click({if (([datetime]::UtcNow-$script:popupClosedAt).TotalMilliseconds -gt 200) {Set-Expanded (-not $ui.DetailsPopup.IsOpen)}})
$ui.DetailsPopup.Add_Closed({$script:popupClosedAt=[datetime]::UtcNow})
$ui.Details.Add_PreviewKeyDown({if ($_.Key -eq 'Escape') {Set-Expanded $false;$_.Handled=$true}})
$window.Add_PreviewKeyDown({if ($_.Key -eq 'Escape') {Set-Expanded $false;$_.Handled=$true}})
$ui.Bar.Add_MouseEnter({$ui.DragHandle.Opacity=0.65})
$ui.Bar.Add_MouseLeave({$ui.DragHandle.Opacity=0})
$ui.PriceSource.Add_Click({Start-Process 'https://developers.openai.com/api/docs/pricing'})
$ui.DragHandle.Add_MouseLeftButtonDown({
 Set-Expanded $false;$script:dragging=$true
 try {
  $window.DragMove()
  if ($null -ne $script:ownerBounds) {
   $bounds=$script:ownerBounds;$available=$bounds.right-$bounds.left-$script:compactWidth
   if ($available -gt 0) {$script:placement.leftRatio=[math]::Max(0,[math]::Min(1,($window.Left-$bounds.left)/$available))}
   $script:placement.bottom=[math]::Max(0,$bounds.bottom-$window.Top-$window.Height)
   $script:placement | ConvertTo-Json | Set-Content -LiteralPath $placementPath -Encoding UTF8
  }
 } finally {$script:dragging=$false}
 $_.Handled=$true
})
$python=Find-MonitorPython $settings
if (-not $python) {throw (L 'MissingPython')}
$startInfo=New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName=$python
$startInfo.Arguments='"'+(Join-Path $PSScriptRoot 'monitor.py')+'" --runtime "'+$runtime+'" --parent-pid '+$PID
$startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true;$startInfo.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$script:worker=[Diagnostics.Process]::Start($startInfo)
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[timespan]::FromMilliseconds(500)
$timer.Add_Tick({
 try {
  if (Test-Path -LiteralPath $stopPath) {$window.Close();return}
  if ($script:ownerPid -gt 0 -and -not (Get-Process -Id $script:ownerPid -ErrorAction SilentlyContinue)) {$window.Close();return}
  Follow-Owner
  $stateFile=Get-Item -LiteralPath (Join-Path $runtime 'state.json') -ErrorAction SilentlyContinue
  if ($null -ne $stateFile -and $stateFile.LastWriteTimeUtc -ne $script:lastStateWrite) {
   try {Set-Usage (Get-Content -LiteralPath $stateFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json);$script:lastStateWrite=$stateFile.LastWriteTimeUtc} catch {throw}
  } else {Update-Age}
  if ($script:worker.HasExited) {$ui.UsageText.Text=L 'RestartRequired'}
 } catch {$_.Exception.Message | Set-Content -LiteralPath (Join-Path $runtime 'timer-error.txt') -Encoding UTF8}
})
$window.Add_Closed({
 $script:closed=$true;$ui.DetailsPopup.IsOpen=$false;$timer.Stop()
 if ($null -ne $script:worker -and -not $script:worker.HasExited) {$script:worker.Kill()}
 $mutex.ReleaseMutex();$mutex.Dispose();[Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})
$window.Show();Follow-Owner;$timer.Start();[Windows.Threading.Dispatcher]::Run()
