import cv2
import numpy as np
import sys

image_path = r"G:\AntigravityPortable\.gemini\antigravity\brain\f06d5484-874a-40c9-9d20-6cbeb9ae93b3\.user_uploaded\media__1788159248098.png"
img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)

if img is None:
    print("Could not read image")
    sys.exit(1)

h, w = img.shape
print("Image size: %d x %d" % (w, h))

# Threshold: anything not white is black
_, thresh = cv2.threshold(img, 240, 255, cv2.THRESH_BINARY_INV)

# Find contours
contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

rects = []
for cnt in contours:
    x, y, cw, ch = cv2.boundingRect(cnt)
    if cw > 50 and ch > 50:
        rects.append((x, y, cw, ch))

rects.sort(key=lambda r: r[1])
for i, r in enumerate(rects):
    print("Rect %d: x=%d, y=%d, w=%d, h=%d" % (i, r[0], r[1], r[2], r[3]))
