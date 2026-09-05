import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CarPanel {
  bumperDepan, spoilerBumperDepan, kapMesin,
  bumperBelakang, spoilerBumperBelakang, bagasi, spoilerBagasi,
  fenderRH, pintuDepanRH, spionRH, pintuBelakangRH, quarterRH, trisplangRH, sideRoofRH,
  fenderLH, pintuDepanLH, spionLH, pintuBelakangLH, quarterLH, trisplangLH, sideRoofLH,
  roof, cover
}

extension CarPanelExtension on CarPanel {
  // Conversions for DB payload syncing (e.g., bumperDepan -> 'bumper_depan')
  String get snakeCaseValue {
    return toString().split('.').last.replaceAllMapped(
      RegExp(r'([A-Z])'), (match) => '_${match.group(1)!.toLowerCase()}'
    ).toLowerCase();
  }

  String get label {
    switch (this) {
      case CarPanel.bumperDepan: return 'Bumper Depan';
      case CarPanel.spoilerBumperDepan: return 'Spoiler Bumper Depan';
      case CarPanel.kapMesin: return 'Kap Mesin';
      case CarPanel.bumperBelakang: return 'Bumper Belakang';
      case CarPanel.spoilerBumperBelakang: return 'Spoiler Bumper Belakang';
      case CarPanel.bagasi: return 'Bagasi';
      case CarPanel.spoilerBagasi: return 'Spoiler Bagasi';
      case CarPanel.fenderRH: return 'Fender RH';
      case CarPanel.pintuDepanRH: return 'Pintu Depan RH';
      case CarPanel.spionRH: return 'Spion RH';
      case CarPanel.pintuBelakangRH: return 'Pintu Belakang RH';
      case CarPanel.quarterRH: return 'Quarter RH';
      case CarPanel.trisplangRH: return 'Trisplang RH';
      case CarPanel.sideRoofRH: return 'Side Roof RH';
      case CarPanel.fenderLH: return 'Fender LH';
      case CarPanel.pintuDepanLH: return 'Pintu Depan LH';
      case CarPanel.spionLH: return 'Spion LH';
      case CarPanel.pintuBelakangLH: return 'Pintu Belakang LH';
      case CarPanel.quarterLH: return 'Quarter LH';
      case CarPanel.trisplangLH: return 'Trisplang LH';
      case CarPanel.sideRoofLH: return 'Side Roof LH';
      case CarPanel.roof: return 'Roof';
      case CarPanel.cover: return 'Cover';
    }
  }
}

class SelectedPanelsNotifier extends StateNotifier<Set<CarPanel>> {
  SelectedPanelsNotifier() : super({});

  void togglePanel(CarPanel panel) {
    if (state.contains(panel)) {
      state = Set.from(state)..remove(panel);
    } else {
      state = Set.from(state)..add(panel);
    }
  }

  void clearSelection() => state = {};
}

final selectedPanelsProvider = StateNotifierProvider<SelectedPanelsNotifier, Set<CarPanel>>((ref) => SelectedPanelsNotifier());
