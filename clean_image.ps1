Add-Type -AssemblyName System.Drawing

$imagePath = "G:\AntigravityPortable\.gemini\antigravity\scratch\re-V\assets\images\car_blueprint.png"
$bmp = New-Object System.Drawing.Bitmap($imagePath)

# We will create a new bitmap that is cropped.
# The original is 978x650. Let's crop 20 pixels from all sides to remove the black border.
$cropRect = New-Object System.Drawing.Rectangle(20, 20, ($bmp.Width - 40), ($bmp.Height - 40))
$croppedBmp = $bmp.Clone($cropRect, $bmp.PixelFormat)

# Now, paint the crown white. The crown is at the top left of the cropped image.
# It is around x=0 to 100, y=0 to 100 in the cropped image.
$graphics = [System.Drawing.Graphics]::FromImage($croppedBmp)
$whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
# Draw a white rectangle over the crown (top left corner)
$graphics.FillRectangle($whiteBrush, 0, 0, 80, 80)

# Save to a new file
$newPath = "G:\AntigravityPortable\.gemini\antigravity\scratch\re-V\assets\images\car_blueprint_clean.png"
$croppedBmp.Save($newPath, [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$whiteBrush.Dispose()
$croppedBmp.Dispose()
$bmp.Dispose()

Write-Host "Image cropped and cleaned successfully."
