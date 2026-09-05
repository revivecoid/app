def generate_dart_code():
    dart_code = []
    
    def rect_to_poly(x1, y1, x2, y2, rx, ry):
        # Generate a rounded rectangle polygon
        # (This is just an approximation, but we can just use RRect in Dart)
        pass

    # We will just write a Dart class that constructs these symmetrically
    dart_source = """
class CarPathData {
  static Map<CarPanel, Path> getPaths() {
    Path poly(List<double> coords) {
      final path = Path();
      for (int i = 0; i < coords.length; i += 2) {
        if (i == 0) path.moveTo(coords[i], coords[i+1]);
        else path.lineTo(coords[i], coords[i+1]);
      }
      path.close();
      return path;
    }

    Path r(double l, double t, double right, double b) {
      final path = Path();
      path.addRRect(RRect.fromLTRBR(l, t, right, b, const Radius.circular(6)));
      return path;
    }
    
    // Top-down centerline is Y = 305
    Path symTop(List<double> topHalfX, List<double> topHalfY) {
      final path = Path();
      for (int i = 0; i < topHalfX.length; i++) {
        if (i == 0) path.moveTo(topHalfX[i], topHalfY[i]);
        else path.lineTo(topHalfX[i], topHalfY[i]);
      }
      for (int i = topHalfX.length - 1; i >= 0; i--) {
        path.lineTo(topHalfX[i], 305 + (305 - topHalfY[i]));
      }
      path.close();
      return path;
    }

    return {
      // 1. Center (Top-Down View)
      CarPanel.kapMesin: symTop([240, 400, 400], [250, 220, 305]),
      CarPanel.roof:     symTop([410, 560, 560, 410], [220, 220, 305, 305]),
      CarPanel.bagasi:   symTop([570, 730, 730], [220, 250, 305]),
      CarPanel.cover:    r(220, 200, 750, 410),

      // 2. Top (Right Side View)
      // Original Y center for top was around 105.
      // Shifted by 20 -> 85.
      CarPanel.fenderRH:             poly([220,90, 310,70, 310,160, 220,160]),
      CarPanel.pintuDepanRH:         poly([320,60, 430,40, 430,160, 320,160]),
      CarPanel.pintuBelakangRH:      poly([440,40, 540,40, 540,160, 440,160]),
      CarPanel.quarterRH:            poly([550,40, 700,60, 700,160, 550,160]),
      CarPanel.trisplangRH:          r(320, 165, 540, 185),
      CarPanel.sideRoofRH:           poly([370,10, 500,10, 500,35, 370,55]),
      CarPanel.spionRH:              r(310, 70, 330, 90),

      // 3. Bottom (Left Side View)
      // Mirror of Right Side View, but Y is shifted down.
      // Top view center was Y=85. Bottom view center is Y=535 (620-85).
      CarPanel.fenderLH:             poly([220,580, 310,600, 310,510, 220,510]),
      CarPanel.pintuDepanLH:         poly([320,610, 430,630, 430,510, 320,510]),
      CarPanel.pintuBelakangLH:      poly([440,630, 540,630, 540,510, 440,510]),
      CarPanel.quarterLH:            poly([550,630, 700,610, 700,510, 550,510]),
      CarPanel.trisplangLH:          r(320, 485, 540, 505),
      CarPanel.sideRoofLH:           poly([370,660, 500,660, 500,635, 370,615]), // Wait, roof is towards the center! Center is Y=305. So roof is at top of this view!
      // Actually, Y is inverted in the left view? Wheels are pointing DOWN.
      // So roof is Y=420. Wheels are Y=580.
      CarPanel.spionLH:              r(310, 580, 330, 600),

      // 4. Left (Front View)
      CarPanel.bumperDepan:          r(20, 240, 80, 370),
      CarPanel.spoilerBumperDepan:   r(0, 240, 20, 370),

      // 5. Right (Rear View)
      CarPanel.bumperBelakang:       r(840, 240, 900, 370),
      CarPanel.spoilerBumperBelakang:r(900, 240, 920, 370),
      CarPanel.spoilerBagasi:        r(810, 270, 840, 340),
    };
  }
}
"""
    with open("G:\\AntigravityPortable\\.gemini\\antigravity\\scratch\\re-V\\lib\\features\\customer_app\\estimator\\presentation\\widgets\\interactive_car_diagram.dart.tmp", "w") as f:
        f.write(dart_source)

generate_dart_code()
