# Draws the Syncro Kiosk icon in the family style (gear, circuit lines, bold 3D letter): K on a gear, on Syncro ink green.
param([string]$Out = 'Z:\SyncroConnect\tmp\kiosk\icon')
Add-Type -AssemblyName System.Drawing
function C($r,$g,$b){ [System.Drawing.Color]::FromArgb(255,$r,$g,$b) }
$bgCol = C 0x10 0x2F 0x08
$gearTop = C 0xF7 0xB7 0x2C; $gearBot = C 0xEA 0x6C 0x1A
$gearEdge = C 0xB8 0x4A 0x10
$kTop = C 0x9F 0xD8 0x4A; $kBot = C 0x5E 0xA8 0x2A; $kShade = C 0x2F 0x6B 0x14
$wire = C 0xF7 0xB7 0x2C

function Gear([float]$cx,[float]$cy,[float]$rOut,[float]$rIn,[int]$teeth) {
  $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  $step = 2*[Math]::PI/$teeth
  for ($i=0; $i -lt $teeth; $i++) {
    $a = $i*$step - [Math]::PI/2
    foreach ($pair in @(@(-0.30,$rIn),@(-0.18,$rOut),@(0.18,$rOut),@(0.30,$rIn))) {
      $ang = $a + $pair[0]*$step*1.0
      $pts.Add((New-Object System.Drawing.PointF([float]($cx+$pair[1]*[Math]::Cos($ang)), [float]($cy+$pair[1]*[Math]::Sin($ang)))))
    }
  }
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon($pts.ToArray()); return $p
}
function KPath([float]$x,[float]$y,[float]$s) {
  # A bold K on a 100-unit grid, scaled by $s from top-left ($x,$y).
  $u = @(@(0,0),@(30,0),@(30,38),@(64,0),@(100,0),@(54,50),@(102,100),@(64,100),@(30,62),@(30,100),@(0,100))
  $pts = foreach ($q in $u) { New-Object System.Drawing.PointF([float]($x+$q[0]*$s),[float]($y+$q[1]*$s)) }
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon([System.Drawing.PointF[]]$pts); return $p
}
function Draw([int]$size,[bool]$rounded,[string]$file) {
  $S=1024
  $bmp = New-Object System.Drawing.Bitmap($S,$S,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g=[System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode='AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
  $bg = New-Object System.Drawing.SolidBrush($bgCol)
  if ($rounded) { $rp=New-Object System.Drawing.Drawing2D.GraphicsPath; $d=460; $rp.AddArc(0,0,$d,$d,180,90); $rp.AddArc($S-$d,0,$d,$d,270,90); $rp.AddArc($S-$d,$S-$d,$d,$d,0,90); $rp.AddArc(0,$S-$d,$d,$d,90,90); $rp.CloseFigure(); $g.FillPath($bg,$rp) } else { $g.FillRectangle($bg,0,0,$S,$S) }
  # circuit wires and rings (behind the gear)
  $pen = New-Object System.Drawing.Pen($wire, 26); $pen.StartCap='Round'; $pen.EndCap='Round'; $pen.LineJoin='Round'
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(640,300)),(New-Object System.Drawing.PointF(760,240)),(New-Object System.Drawing.PointF(800,240))))
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(370,712)),(New-Object System.Drawing.PointF(250,772)),(New-Object System.Drawing.PointF(215,772))))
  $ringPen = New-Object System.Drawing.Pen($wire, 26)
  $g.DrawEllipse($ringPen, 790, 196, 88, 88); $g.DrawEllipse($ringPen, 130, 728, 88, 88)
  $wb = New-Object System.Drawing.SolidBrush($wire); $g.FillEllipse($wb, 818, 224, 32, 32); $g.FillEllipse($wb, 158, 756, 32, 32)
  # gear ring with edge
  $gear = Gear 512 512 330 268 14
  $hole = New-Object System.Drawing.Drawing2D.GraphicsPath; $hole.AddEllipse(512-175,512-175,350,350)
  $ring = New-Object System.Drawing.Region($gear); $ring.Exclude($hole)
  $edgeRegion = New-Object System.Drawing.Region((Gear 520 524 330 268 14)); $edgeRegion.Exclude($hole)
  $g.FillRegion((New-Object System.Drawing.SolidBrush($gearEdge)), $edgeRegion)
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,180)),(New-Object System.Drawing.Point(0,850)),$gearTop,$gearBot)
  $g.FillRegion($lg, $ring)
  # wire end dots on the gear
  $g.FillEllipse($wb, 612, 272, 56, 56); $g.FillEllipse($wb, 342, 684, 56, 56)
  # 3D K: shade offset then face
  $g.FillPath((New-Object System.Drawing.SolidBrush($kShade)), (KPath 352 322 3.3))
  $kg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,300)),(New-Object System.Drawing.Point(0,640)),$kTop,$kBot)
  $g.FillPath($kg, (KPath 336 306 3.3))
  $g.Dispose()
  $out = New-Object System.Drawing.Bitmap($size,$size,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g2=[System.Drawing.Graphics]::FromImage($out); $g2.InterpolationMode='HighQualityBicubic'; $g2.SmoothingMode='AntiAlias'; $g2.PixelOffsetMode='HighQuality'; $g2.DrawImage($bmp,0,0,$size,$size); $g2.Dispose(); $bmp.Dispose()
  if (-not $rounded) { $flat=New-Object System.Drawing.Bitmap($size,$size,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb); $g3=[System.Drawing.Graphics]::FromImage($flat); $g3.DrawImage($out,0,0,$size,$size); $g3.Dispose(); $out.Dispose(); $out=$flat }
  $out.Save($file,[System.Drawing.Imaging.ImageFormat]::Png); $out.Dispose()
}
$android=@{'mdpi'=48;'hdpi'=72;'xhdpi'=96;'xxhdpi'=144;'xxxhdpi'=192}
foreach($k in $android.Keys){ New-Item -ItemType Directory -Force -Path "$Out\android\mipmap-$k" | Out-Null; Draw $android[$k] $false "$Out\android\mipmap-$k\ic_launcher.png" }
Draw 512 $false "$Out\app-icon.png"; Draw 1024 $false "$Out\preview-1024.png"
New-Item -ItemType Directory -Force -Path "$Out\ios" | Out-Null
$ios=@{'20x20@1x'=20;'20x20@2x'=40;'20x20@3x'=60;'29x29@1x'=29;'29x29@2x'=58;'29x29@3x'=87;'40x40@1x'=40;'40x40@2x'=80;'40x40@3x'=120;'60x60@2x'=120;'60x60@3x'=180;'76x76@1x'=76;'76x76@2x'=152;'83.5x83.5@2x'=167;'1024x1024@1x'=1024}
foreach($k in $ios.Keys){ Draw $ios[$k] $false "$Out\ios\Icon-App-$k.png" }
'done'
