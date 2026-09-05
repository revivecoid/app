Add-Type -AssemblyName System.Drawing

$imagePath = "G:\AntigravityPortable\.gemini\antigravity\scratch\re-V\assets\images\car_blueprint.png"
$bmp = New-Object System.Drawing.Bitmap($imagePath)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Blue, 2)

# Top car (Right Side View)
# Mirror is drawn inside the car at X=310, Y=90
$graphics.DrawRectangle($pen, 305, 80, 25, 20)

# Bottom car (Left Side View)
$graphics.DrawRectangle($pen, 305, 510, 25, 20)

# Center view (Top-Down)
$graphics.DrawRectangle($pen, 340, 215, 20, 15) # Right mirror
$graphics.DrawRectangle($pen, 340, 380, 20, 15) # Left mirror

# Front view (Left car)
$graphics.DrawRectangle($pen, 130, 220, 15, 25) # Right mirror (top)
$graphics.DrawRectangle($pen, 130, 365, 15, 25) # Left mirror (bottom)

# Rear view (Right car)
$graphics.DrawRectangle($pen, 785, 220, 15, 25) # Left mirror (top)
$graphics.DrawRectangle($pen, 785, 365, 15, 25) # Right mirror (bottom)

$newPath = "G:\AntigravityPortable\.gemini\antigravity\scratch\re-V\test_spion3.png"
$bmp.Save($newPath, [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$pen.Dispose()
$bmp.Dispose()
