import 'package:flutter/material.dart';
import '../../providers/panel_selection_provider.dart';

class InteractiveCarDiagram extends StatelessWidget {
  final Set<CarPanel> selectedPanels;
  final Function(CarPanel) onToggle;

  const InteractiveCarDiagram({
    Key? key,
    required this.selectedPanels,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Image original size is 938 x 610 (after border removal)
        const double imgW = 938.0;
        const double imgH = 610.0;
        
        final width = constraints.maxWidth;
        final height = width * (imgH / imgW);

        return Center(
          child: GestureDetector(
            onTapUp: (TapUpDetails details) {
              final tapX = details.localPosition.dx * (imgW / width);
              final tapY = details.localPosition.dy * (imgH / height);
              final tapPosition = Offset(tapX, tapY);
              
              final carPaths = CarPathData.getPaths();
              for (final entry in carPaths.entries) {
                if (entry.value.contains(tapPosition)) {
                  onToggle(entry.key);
                  break;
                }
              }
            },
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/car_blueprint.png',
                        fit: BoxFit.contain,
                        color: Colors.white.withValues(alpha: 0.9),
                        colorBlendMode: BlendMode.modulate,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CarDiagramPainter(
                        selectedPanels: selectedPanels,
                        carPaths: CarPathData.getPaths(),
                        scaleX: width / imgW,
                        scaleY: height / imgH,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class CarDiagramPainter extends CustomPainter {
  final Set<CarPanel> selectedPanels;
  final Map<CarPanel, Path> carPaths;
  final double scaleX;
  final double scaleY;

  CarDiagramPainter({
    required this.selectedPanels,
    required this.carPaths,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scaleX, scaleY);

    for (final entry in carPaths.entries) {
      final panel = entry.key;
      final path = entry.value;
      final isSelected = selectedPanels.contains(panel);

      if (isSelected) {
        canvas.drawPath(path, Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill);
        canvas.drawPath(path, Paint()
          ..color = Colors.redAccent.shade100
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.5 / scaleX);
      } else {
        canvas.drawPath(path, Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.0)
          ..style = PaintingStyle.fill);
        canvas.drawPath(path, Paint()
          ..color = Colors.blue.withValues(alpha: 0.0)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.0 / scaleX);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CarDiagramPainter old) =>
      old.selectedPanels != selectedPanels;
}

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

    // Mirror perfectly around the center of the image (Y=305)
    Path mirrorBottom(List<double> topCoords) {
      final path = Path();
      for (int i = 0; i < topCoords.length; i += 2) {
        if (i == 0) path.moveTo(topCoords[i], 610 - topCoords[i+1]);
        else path.lineTo(topCoords[i], 610 - topCoords[i+1]);
      }
      path.close();
      return path;
    }
    
    Path multiPoly(List<List<double>> polys) {
      final path = Path();
      for (final coords in polys) {
        for (int i = 0; i < coords.length; i += 2) {
          if (i == 0) path.moveTo(coords[i], coords[i+1]);
          else path.lineTo(coords[i], coords[i+1]);
        }
        path.close();
      }
      return path;
    }

    // Right Side View (Top) - Perfectly Flush Seams
    final rhFender = <double>[200,105, 230,85, 310,70, 310,165, 200,165];
    final rhPintuDepan = <double>[310,70, 455,70, 455,165, 310,165];
    final rhPintuBelakang = <double>[455,70, 565,70, 565,165, 455,165];
    final rhQuarter = <double>[565,70, 680,85, 730,105, 730,165, 565,165];
    final rhTrisplang = <double>[310,165, 565,165, 565,185, 310,185];
    final rhSideRoof = <double>[380,25, 480,25, 565,70, 310,70];

    return {
      // 0. Mirrors (Hit-tested FIRST because they are small and overlap doors)
      CarPanel.spionRH:              multiPoly([
        <double>[315,85, 335,85, 335,105, 315,105], // Side view
        <double>[345,215, 365,215, 365,230, 345,230], // Center view
        <double>[130,225, 145,225, 145,250, 130,250], // Front view
        <double>[795,225, 810,225, 810,250, 795,250], // Rear view
      ]),
      CarPanel.spionLH:              multiPoly([
        <double>[315,505, 335,505, 335,525, 315,525], // Side view
        <double>[345,380, 365,380, 365,395, 345,395], // Center view
        <double>[130,360, 145,360, 145,385, 130,385], // Front view
        <double>[795,360, 810,360, 810,385, 795,385], // Rear view
      ]),

      // 1. Center (Top-Down View)
      CarPanel.kapMesin: symTop(<double>[210, 310, 360, 390], <double>[250, 245, 235, 230]),
      CarPanel.roof:     symTop(<double>[390, 460, 560, 570], <double>[230, 225, 225, 230]),
      CarPanel.bagasi:   symTop(<double>[570, 620, 700, 755], <double>[230, 235, 245, 250]),
      CarPanel.cover:    symTop(<double>[200, 755], <double>[220, 220]), // Fallback

      // 2. Top (Right Side View)
      CarPanel.fenderRH:             poly(rhFender),
      CarPanel.pintuDepanRH:         poly(rhPintuDepan),
      CarPanel.pintuBelakangRH:      poly(rhPintuBelakang),
      CarPanel.quarterRH:            poly(rhQuarter),
      CarPanel.trisplangRH:          poly(rhTrisplang),
      CarPanel.sideRoofRH:           poly(rhSideRoof),

      // 3. Bottom (Left Side View - Perfectly symmetric!)
      CarPanel.fenderLH:             mirrorBottom(rhFender),
      CarPanel.pintuDepanLH:         mirrorBottom(rhPintuDepan),
      CarPanel.pintuBelakangLH:      mirrorBottom(rhPintuBelakang),
      CarPanel.quarterLH:            mirrorBottom(rhQuarter),
      CarPanel.trisplangLH:          mirrorBottom(rhTrisplang),
      CarPanel.sideRoofLH:           mirrorBottom(rhSideRoof),

      // 4. Left (Front View)
      CarPanel.bumperDepan:          poly(<double>[25,255, 65,245, 95,255, 95,355, 65,365, 25,355]),
      CarPanel.spoilerBumperDepan:   poly(<double>[10,265, 20,265, 20,345, 10,345]),

      // 5. Right (Rear View)
      CarPanel.bumperBelakang:       poly(<double>[845,255, 875,245, 915,255, 915,355, 875,365, 845,355]),
      CarPanel.spoilerBumperBelakang:poly(<double>[920,265, 930,265, 930,345, 920,345]),
      CarPanel.spoilerBagasi:        poly(<double>[830,265, 840,265, 840,345, 830,345]),
    };
  }
}
