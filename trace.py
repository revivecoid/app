import cv2
import numpy as np
import json

# Read the image
image_path = r"G:\AntigravityPortable\.gemini\antigravity\brain\f06d5484-874a-40c9-9d20-6cbeb9ae93b3\.user_uploaded\media__1788159248098.png"
img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)

# Threshold to get black lines
_, thresh = cv2.threshold(img, 200, 255, cv2.THRESH_BINARY_INV)

# Find contours
contours, hierarchy = cv2.findContours(thresh, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

print(f"Found {len(contours)} contours")
