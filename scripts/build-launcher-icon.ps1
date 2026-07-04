# Build launcher icon PNG from app_logo.png (keeps original untouched).
param(
    [Parameter(Mandatory = $true)]
    [string]$LogoPath,
    [Parameter(Mandatory = $true)]
    [string]$OutPath,
    [int]$Size = 1024,
    [double]$MarginRatio = 0.12
)

Add-Type -AssemblyName System.Drawing

function Test-ContentPixel([System.Drawing.Color]$c) {
    if ($c.A -lt 16) { return $false }
    if ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { return $false }
    return $true
}

$src = [System.Drawing.Bitmap]::FromFile($LogoPath)
try {
    $minX = $src.Width; $minY = $src.Height; $maxX = 0; $maxY = 0
    for ($y = 0; $y -lt $src.Height; $y++) {
        for ($x = 0; $x -lt $src.Width; $x++) {
            if (Test-ContentPixel $src.GetPixel($x, $y)) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -le $minX) {
        throw "No visible logo content in $LogoPath"
    }

    $cropW = $maxX - $minX + 1
    $cropH = $maxY - $minY + 1
    $crop = New-Object System.Drawing.Bitmap $cropW, $cropH
    $gCrop = [System.Drawing.Graphics]::FromImage($crop)
    $gCrop.DrawImage($src, 0, 0, (New-Object System.Drawing.Rectangle $minX, $minY, $cropW, $cropH), [System.Drawing.GraphicsUnit]::Pixel)
    $gCrop.Dispose()

    $margin = [int]($Size * $MarginRatio)
    $target = $Size - (2 * $margin)
    $scale = [Math]::Min($target / $cropW, $target / $cropH)
    $newW = [int]($cropW * $scale)
    $newH = [int]($cropH * $scale)

    $out = New-Object System.Drawing.Bitmap $Size, $Size
    $gOut = [System.Drawing.Graphics]::FromImage($out)
    $gOut.Clear([System.Drawing.Color]::White)
    $gOut.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gOut.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gOut.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $ox = [int](($Size - $newW) / 2)
    $oy = [int](($Size - $newH) / 2)
    $gOut.DrawImage($crop, $ox, $oy, $newW, $newH)
    $gOut.Dispose()
    $crop.Dispose()

    $dir = Split-Path $OutPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    Write-Host "Created $OutPath (${cropW}x${cropH} content -> ${Size}x${Size})"
}
finally {
    $src.Dispose()
}
