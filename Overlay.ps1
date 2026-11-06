param([switch]$ValidateOnly, [switch]$RenderPreview, [string]$PreviewState, [string]$PreviewOutput, [string]$Language)
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:LOCALAPPDATA 'CodexContextMonitor'
[void][IO.Directory]::CreateDirectory($runtime)
trap {
    ($_ | Out-String) | Set-Content -LiteralPath (Join-Path $runtime 'overlay-error.txt') -Encoding UTF8
    exit 1
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies WindowsBase,PresentationCore,PresentationFramework,System.Xaml -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
namespace ContextMeter {
    public class Ring : FrameworkElement {
        private double percent;
        public double Percent { get { return percent; } set { percent = value; InvalidateVisual(); } }
        protected override void OnRender(DrawingContext dc) {
            double radius = Math.Max(1, Math.Min(ActualWidth, ActualHeight) / 2 - 1.5);
            Point center = new Point(ActualWidth / 2, ActualHeight / 2);
            dc.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromRgb(72,72,78)), 1.6), center, radius, radius);
            if (Double.IsNaN(percent) || percent <= 0) return;
            double fraction = Math.Min(percent, 99.999) / 100;
            double angle = fraction * 2 * Math.PI - Math.PI / 2;
            Color color = percent >= 90 ? Color.FromRgb(184,156,110) : Color.FromRgb(153,153,162);
            var pen = new Pen(new SolidColorBrush(color), 1.6) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            var geometry = new StreamGeometry();
            using (var ctx = geometry.Open()) {
                ctx.BeginFigure(new Point(center.X, center.Y-radius), false, false);
                ctx.ArcTo(new Point(center.X + radius*Math.Cos(angle), center.Y + radius*Math.Sin(angle)), new Size(radius,radius), 0, fraction > .5, SweepDirection.Clockwise, true, false);
            }
            dc.DrawGeometry(null, pen, geometry);
        }
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
        [DllImport("kernel32.dll")] public static extern ushort GetUserDefaultUILanguage();
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    }
}
'@

[xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Overlay.xaml') -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$ui = @{}
foreach ($node in $xaml.SelectNodes('//*[@Name]')) { $ui[$node.Name] = $window.FindName($node.Name) }
$ring = New-Object ContextMeter.Ring
$ui.RingHost.Children.Add($ring) | Out-Null
if ($ValidateOnly) { Write-Output 'XAML and native helper compiled successfully.'; exit 0 }
. (Join-Path $PSScriptRoot 'Settings.ps1')
$settings=Get-MonitorSettings
$systemLanguage=[Globalization.CultureInfo]::GetCultureInfo([int][ContextMeter.Native]::GetUserDefaultUILanguage()).Name
$selectedLanguage=Resolve-MonitorLanguage $(if ($Language) {$Language} else {$settings.language}) $systemLanguage
$script:strings=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('locales/'+$selectedLanguage+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
function L([string]$key) {return $script:strings.$key}
foreach ($key in @('ContextWindow','CachedInput','NewInput','Output','Remaining','ModelUsage')) {$ui[('Label'+$key)].Text=L $key}
$ui.DragHandle.ToolTip=L 'Drag';$ui.SpeedLarge.ToolTip=L 'SpeedHelp';$ui.CacheLarge.ToolTip=L 'CacheHelp'
$ui.EmptyModels.Text=L 'Waiting';$ui.PriceLabel.Text=L 'Estimate'
. (Join-Path $PSScriptRoot 'OverlayRuntime.ps1')
