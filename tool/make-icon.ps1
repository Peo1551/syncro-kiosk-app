# Draws the Syncro Kiosk icon: lime kiosk tablet on a stand with an S, on Syncro ink green.
param([string]$Out = 'Z:\SyncroConnect\tmp\kiosk\icon')
Add-Type -AssemblyName System.Drawing
$ink  = [System.Drawing.Color]::FromArgb(255, 0x10, 0x2F, 0x08)
$lime = [System.Drawing.Color]::FromArgb(255, 0x8D, 0xC6, 0x3E)
$pale = [System.Drawing.Color]::FromArgb(255, 0xC3, 0xDC, 0x29)

function RoundRect([float]$x,[float]$y,[float]$w,[float]$h,[float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2*$r
  $p.AddArc($x,$y,$d,$d,180,90); $p.AddArc($x+$w-$d,$y,$d,$d,270,90)
  $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90); $p.AddArc($x,$y+$h-$d,$d,$d,90,90)
  $p.CloseFigure(); return $p
}

function Draw([int]$size, [bool]$rounded, [string]$file) {
  $S = 1024
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.Clear([System.Drawing.Color]::Transparent)
  $bg = New-Object System.Drawing.SolidBrush($ink)
  if ($rounded) { $g.FillPath($bg, (RoundRect 0 0 $S $S 230)) } else { $g.FillRectangle($bg, 0, 0, $S, $S) }
  # stand
  $limeB = New-Object System.Drawing.SolidBrush($lime)
  $stand = New-Object System.Drawing.Drawing2D.GraphicsPath
  $stand.AddPolygon([System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(452,690)),(New-Object System.Drawing.PointF(572,690)),(New-Object System.Drawing.PointF(600,820)),(New-Object System.Drawing.PointF(424,820))))
  $g.FillPath($limeB, $stand)
  $g.FillPath($limeB, (RoundRect 330 800 364 56 28))
  # tablet body and screen
  $g.FillPath($limeB, (RoundRect 196 196 632 500 64))
  $g.FillPath($bg, (RoundRect 236 236 552 420 34))
  # S on the screen
  $font = New-Object System.Drawing.Font('Segoe UI', 300, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $paleB = New-Object System.Drawing.SolidBrush($pale)
  $g.DrawString('S', $font, $paleB, (New-Object System.Drawing.RectangleF(236, 236, 552, 440)), $fmt)
  $g.Dispose()
  $outBmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g2 = [System.Drawing.Graphics]::FromImage($outBmp)
  $g2.InterpolationMode = 'HighQualityBicubic'; $g2.SmoothingMode = 'AntiAlias'; $g2.PixelOffsetMode = 'HighQuality'
  $g2.DrawImage($bmp, 0, 0, $size, $size); $g2.Dispose(); $bmp.Dispose()
  if (-not $rounded) {
    # iOS: no transparency
    $flat = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g3 = [System.Drawing.Graphics]::FromImage($flat); $g3.DrawImage($outBmp, 0, 0, $size, $size); $g3.Dispose()
    $outBmp.Dispose(); $outBmp = $flat
  }
  $outBmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $outBmp.Dispose()
}

$android = @{ 'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192 }
foreach ($k in $android.Keys) { New-Item -ItemType Directory -Force -Path "$Out\android\mipmap-$k" | Out-Null; Draw $android[$k] $true "$Out\android\mipmap-$k\ic_launcher.png" }
Draw 512 $true "$Out\app-icon.png"
Draw 1024 $true "$Out\preview-1024.png"
New-Item -ItemType Directory -Force -Path "$Out\ios" | Out-Null
$ios = @{ '20x20@1x'=20; '20x20@2x'=40; '20x20@3x'=60; '29x29@1x'=29; '29x29@2x'=58; '29x29@3x'=87; '40x40@1x'=40; '40x40@2x'=80; '40x40@3x'=120; '60x60@2x'=120; '60x60@3x'=180; '76x76@1x'=76; '76x76@2x'=152; '83.5x83.5@2x'=167; '1024x1024@1x'=1024 }
foreach ($k in $ios.Keys) { Draw $ios[$k] $false "$Out\ios\Icon-App-$k.png" }
'done'
