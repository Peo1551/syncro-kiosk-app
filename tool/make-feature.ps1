Add-Type -AssemblyName System.Drawing
$W=1024; $H=500
$bmp = New-Object System.Drawing.Bitmap($W,$H,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g=[System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAliasGridFit'; $g.InterpolationMode='HighQualityBicubic'
$ink=[System.Drawing.Color]::FromArgb(255,0x10,0x2F,0x08); $lime=[System.Drawing.Color]::FromArgb(255,0x8D,0xC6,0x3E)
$g.Clear($ink)
# soft lime arc accent
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,0x8D,0xC6,0x3E), 60)
$g.DrawEllipse($pen, 620, -220, 700, 700)
$icon=New-Object System.Drawing.Bitmap('Z:\SyncroConnect\tmp\kiosk\icon\preview-1024.png'); $icon.MakeTransparent($icon.GetPixel(2,2))
$ia=New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY); $g.PixelOffsetMode='HighQuality'; $g.DrawImage($icon,(New-Object System.Drawing.Rectangle(70,90,320,320)),8,8,($icon.Width-16),($icon.Height-16),[System.Drawing.GraphicsUnit]::Pixel,$ia)
$white=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$limeB=New-Object System.Drawing.SolidBrush($lime)
$f1=New-Object System.Drawing.Font('Segoe UI',64,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
$f2=New-Object System.Drawing.Font('Segoe UI',30,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Syncro Kiosk',$f1,$white,430,150)
$g.DrawString('Employee self-service',$f2,$limeB,436,245)
$g.DrawString('on a shared tablet',$f2,$limeB,436,288)
$g.Dispose(); $icon.Dispose()
$bmp.Save('Z:\SyncroConnect\tmp\kiosk\store\feature-graphic-1024x500.png',[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Copy-Item 'Z:\SyncroConnect\tmp\kiosk\icon\app-icon.png' 'Z:\SyncroConnect\tmp\kiosk\store\app-icon-512.png'
'done'
