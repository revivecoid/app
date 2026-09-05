import cv2
import numpy as np

# Load the image
img_path = "G:\\AntigravityPortable\\.gemini\\antigravity\\brain\\f06d5484-874a-40c9-9d20-6cbeb9ae93b3\\car_blueprint.png"
img = cv2.imread(img_path)
if img is None:
    print("Could not load image")
    exit(1)

overlay = img.copy()

def draw_poly(coords, color=(0, 0, 255)):
    pts = np.array(coords, np.int32).reshape((-1, 1, 2))
    cv2.fillPoly(overlay, [pts], color)

# Right Side View (Top)
rh_fender = [200,100, 230,85, 305,80, 305,165, 200,165]
rh_pintu_depan = [310,75, 455,75, 455,165, 310,165]
rh_pintu_belakang = [460,75, 570,75, 570,165, 460,165]
rh_quarter = [575,75, 680,85, 730,105, 730,165, 575,165]
rh_trisplang = [310,170, 570,170, 570,185, 310,185]
rh_roof = [355,25, 515,25, 555,70, 320,70]

draw_poly(rh_fender, (0,0,255))
draw_poly(rh_pintu_depan, (0,255,0))
draw_poly(rh_pintu_belakang, (255,0,0))
draw_poly(rh_quarter, (0,255,255))
draw_poly(rh_trisplang, (255,0,255))
draw_poly(rh_roof, (255,255,0))

# Left Side View (Bottom) - Mirrored
def mirror(coords):
    res = []
    for i in range(0, len(coords), 2):
        res.append(coords[i])
        res.append(610 - coords[i+1])
    return res

draw_poly(mirror(rh_fender), (0,0,255))
draw_poly(mirror(rh_pintu_depan), (0,255,0))
draw_poly(mirror(rh_pintu_belakang), (255,0,0))
draw_poly(mirror(rh_quarter), (0,255,255))
draw_poly(mirror(rh_trisplang), (255,0,255))
draw_poly(mirror(rh_roof), (255,255,0))

# Front View (Left)
# Center is Y=305
front_bumper = [40,265, 95,260, 95,350, 40,345]
draw_poly(front_bumper, (0,0,255))

# Rear View (Right)
rear_bumper = [845,260, 895,265, 895,345, 845,350]
draw_poly(rear_bumper, (0,0,255))

# Top-Down View (Center)
# Center is Y=305
def sym_top(coords_x, coords_y):
    pts = []
    for x, y in zip(coords_x, coords_y):
        pts.extend([x, y])
    for x, y in zip(reversed(coords_x), reversed(coords_y)):
        pts.extend([x, 305 + (305 - y)])
    return pts

top_hood = sym_top([210, 310, 360, 390], [250, 245, 235, 230])
top_roof = sym_top([395, 460, 560, 570], [230, 225, 225, 230])
top_trunk = sym_top([575, 620, 700, 755], [230, 235, 245, 250])

draw_poly(top_hood, (0,0,255))
draw_poly(top_roof, (0,255,0))
draw_poly(top_trunk, (255,0,0))

# Blend with original
alpha = 0.4
cv2.addWeighted(overlay, alpha, img, 1 - alpha, 0, img)

cv2.imwrite("G:\\AntigravityPortable\\.gemini\\antigravity\\brain\\f06d5484-874a-40c9-9d20-6cbeb9ae93b3\\test_overlay.png", img)
print("Saved test_overlay.png")
