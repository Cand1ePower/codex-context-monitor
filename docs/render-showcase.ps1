param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'images'))
# Render a clearly labeled illustrative app scene. This does not capture or control a desktop.
# The overlay images come from Overlay.ps1 -RenderPreview with tests/demo-state.json.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$copy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'showcase-text.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$brushConverter = New-Object Windows.Media.BrushConverter
function Brush([string]$color) { return $brushConverter.ConvertFromString($color) }
function Place($element, [double]$x, [double]$y) {
 [Windows.Controls.Canvas]::SetLeft($element,$x)
 [Windows.Controls.Canvas]::SetTop($element,$y)
 [void]$script:scene.Children.Add($element)
}
function Box([double]$x,[double]$y,[double]$width,[double]$height,[string]$color,[double]$radius=0,[string]$stroke='') {
 $r=New-Object Windows.Shapes.Rectangle
 $r.Width=$width;$r.Height=$height;$r.Fill=Brush $color;$r.RadiusX=$radius;$r.RadiusY=$radius
 if ($stroke) {$r.Stroke=Brush $stroke;$r.StrokeThickness=1}
 Place $r $x $y
}
function Text([string]$value,[double]$x,[double]$y,[double]$size=18,[string]$color='#E9E9EB',[double]$width=0,[string]$weight='Normal') {
 $t=New-Object Windows.Controls.TextBlock
 $t.Text=$value;$t.FontSize=$size;$t.FontFamily=$script:sceneFont;$t.Foreground=Brush $color
 $t.FontWeight=if ($weight -eq 'SemiBold') {[Windows.FontWeights]::SemiBold} else {[Windows.FontWeights]::Normal}
 $t.TextWrapping='Wrap';$t.LineHeight=$size*1.55
 if ($width -gt 0) {$t.Width=$width}
 Place $t $x $y
}
function Glyph([int]$code,[double]$x,[double]$y,[double]$size=22,[string]$color='#929298') {
 $t=New-Object Windows.Controls.TextBlock
 $t.Text=[char]$code;$t.FontSize=$size;$t.FontFamily='Segoe MDL2 Assets';$t.Foreground=Brush $color
 Place $t $x $y
}
function Picture([string]$path,[double]$x,[double]$y,[double]$width) {
 $bitmap=New-Object Windows.Media.Imaging.BitmapImage
 $bitmap.BeginInit();$bitmap.CacheOption='OnLoad';$bitmap.UriSource=[Uri][IO.Path]::GetFullPath($path);$bitmap.EndInit();$bitmap.Freeze()
 $img=New-Object Windows.Controls.Image;$img.Source=$bitmap;$img.Width=$width;$img.Height=$width*$bitmap.PixelHeight/$bitmap.PixelWidth
 Place $img $x $y
}
function Outline([string]$data,[double]$x,[double]$y,[double]$width,[double]$height,[string]$color='#929298') {
 $shape=New-Object Windows.Shapes.Path
 $shape.Data=[Windows.Media.Geometry]::Parse($data);$shape.Stroke=Brush $color;$shape.StrokeThickness=1.5
 $shape.Width=$width;$shape.Height=$height;$shape.Stretch='Uniform'
 Place $shape $x $y
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
foreach ($language in @('en-US','zh-CN')) {
 $s=$copy.$language
 $script:sceneFont=if ($language -eq 'zh-CN') {'Microsoft YaHei UI'} else {'Segoe UI'}
 foreach ($mode in @('collapsed','expanded')) {
 $script:scene=New-Object Windows.Controls.Canvas
 $scene.Width=1920;$scene.Height=1200;$scene.Background=Brush '#181818'
 [Windows.Media.RenderOptions]::SetBitmapScalingMode($scene,'HighQuality')
 Box 0 0 1920 56 '#211F25'
 Glyph 0xE72B 20 18 19;Glyph 0xE72A 63 18 19;Glyph 0xE700 105 18 19
 Text $s.menu 153 14 18 '#959399' 400
 Glyph 0xE921 1774 20 15;Glyph 0xE922 1834 20 15;Glyph 0xE8BB 1892 20 15
 Box 0 56 67 1144 '#211F25'
 Box 67 56 276 1144 '#1D1C20'
 Box 342 56 1 1144 '#333237'
 Box 11 74 45 45 '#343339' 14
 Glyph 0xE80F 23 87 22 '#FFFFFF'
 Glyph 0xE81C 23 147;Glyph 0xE787 23 207;Glyph 0xE8F1 23 267;Glyph 0xE712 23 327
 Box 18 394 31 1 '#39373E'
 Outline 'M0,4 L9,4 L12,7 L26,7 L26,23 L0,23 Z' 23 424 22 19
 Glyph 0xE713 23 1090
 Box 20 1139 28 28 '#6B49A3' 14
 Text 'D' 28 1143 13 '#F8F6FF'
 Text 'Codex' 91 80 23 '#F4F4F5' 160 'SemiBold'
 Glyph 0xE70D 178 91 12;Glyph 0xE721 306 87 19
 Glyph 0xE70F 91 145 20;Text $s.newChat 122 139 18 '#DEDEE2' 190
 Text $s.projects 91 213 12 '#828087' 220 'SemiBold'
 Outline 'M0,4 L9,4 L12,7 L26,7 L26,23 L0,23 Z' 91 255 20 17
 Text $s.workspace 122 247 17 '#D3D1D7' 192
 Box 85 287 242 44 '#303033' 12
 Text $s.chat 106 295 16 '#EEEEF0' 212
 Text $s.recent 91 384 12 '#828087' 220 'SemiBold'
 Text $s.otherChat 105 423 16 '#ADABB2' 210
 Text $s.chat 373 80 20 '#F3F3F5' 880 'SemiBold'
 Text $s.demo 1457 85 12 '#85818F' 425
 Text $s.$mode 1457 147 13 '#A7A1B3' 425
 Box 343 123 1577 1 '#242426'
 Box 758 218 572 72 '#52328B' 24
 Text $s.prompt 780 236 20 '#F8F5FF' 528
 Text $s.worked 473 346 15 '#8C8992' 600
 Box 473 382 857 1 '#333235'
 Text $s.reply 473 415 22 '#E8E8EB' 852
 $rowY=524
 foreach ($feature in @($s.feature1,$s.feature2,$s.feature3)) {
  Box 476 ($rowY+11) 5 5 '#A7A5AF' 2.5
  Text $feature 495 $rowY 19 '#C7C5CD' 810
  $rowY+=42
 }
 Box 473 684 857 208 '#222224' 18 '#37363B'
 Box 489 700 45 45 '#181819' 12
 Outline 'M1,1 L14,1 L21,8 L21,26 L1,26 Z M14,1 L14,8 L21,8' 501 710 20 25 '#B6B2BE'
 Text $s.edited 550 701 20 '#F0EFF3' 500 'SemiBold'
 Text '+128  -12' 550 732 16 '#35BC8A' 300
 Box 1152 706 158 39 '#28272A' 19 '#444149'
 Text $s.changes 1173 712 16 '#E4E1E9' 132
 Box 473 764 857 1 '#39373D'
 $fileY=778
 foreach ($file in @(@('src/App.tsx','+64'),@('src/NotesList.tsx','+42'),@('src/styles.css','+22'))) {
  Text $file[0] 493 $fileY 16 '#B6B3BE' 680
  Text $file[1] 1260 $fileY 16 '#35BC8A' 58
  $fileY+=35
 }
 Text $s.checked 473 926 19 '#D7D4DE' 820
 Glyph 0xE8C8 476 970 16;Glyph 0xE8E1 514 970 16;Glyph 0xE767 552 970 16;Glyph 0xE712 590 970 16
 Box 473 1041 857 132 '#323232' 26 '#424145'
 Text $s.placeholder 495 1059 21 '#939098' 796
 Glyph 0xE710 495 1132 20 '#E1DFE7'
 Glyph 0xE72E 538 1133 17 '#F0844D'
 Text $s.access 565 1127 16 '#F0844D' 250
 Text 'GPT-6 Astra Max' 1029 1128 17 '#D5D2DA' 220
 Glyph 0xE70D 1204 1136 10;Glyph 0xE720 1236 1132 20 '#C8C4D0'
 Box 1279 1121 36 36 '#8050CF' 18
 Glyph 0xE74A 1288 1130 18 '#FFFFFF'
 $suffix=if ($language -eq 'zh-CN') {'zh'} else {'en'}
 if ($mode -eq 'expanded') {
  Text $s.monitor 1465 577 12 '#9993A5' 435
  Picture (Join-Path $PSScriptRoot ('images/panel-'+$suffix+'.png')) 1465 617 435
 }
 Picture (Join-Path $PSScriptRoot ('images/bar-'+$suffix+'.png')) 1582.5 1110 317.5
 $scene.Measure((New-Object Windows.Size(1920,1200)))
 $scene.Arrange((New-Object Windows.Rect(0,0,1920,1200)));$scene.UpdateLayout()
 $render=New-Object Windows.Media.Imaging.RenderTargetBitmap(1920,1200,96,96,([Windows.Media.PixelFormats]::Pbgra32))
 $render.Render($scene)
 $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
 $filename=if ($mode -eq 'collapsed') {'full-window-collapsed-'+$suffix+'.png'} else {'full-window-'+$suffix+'.png'}
 $target=Join-Path $OutputDirectory $filename
 $stream=[IO.File]::Create($target)
 try {$encoder.Save($stream)} finally {$stream.Dispose()}
 Write-Output $target
 }
}
