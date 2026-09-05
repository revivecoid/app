class PricingMatrix {
  static const Map<String, double> basePanelPrices = {
    'Bumper Depan': 500500,
    'Spoiler Bumper depan': 286000,
    'Kap Mesin': 715000,
    'Bumper Belakang': 500500,
    'Spoiler Bumper Belakang': 286000,
    'Bagasi': 643500,
    'Spoiler Bagasi': 286000,
    'Fender RH': 572000,
    'Pintu Depan RH': 572000,
    'Spion RH': 143000,
    'Pintu Belakang RH': 572000,
    'Quarter RH': 572000,
    'Trisplang RH': 357500,
    'Side Roof RH': 357500,
    'Fender LH': 572000,
    'Pintu Depan LH': 572000,
    'Spion LH': 143000,
    'Pintu Belakang LH': 572000,
    'Quarter LH': 572000,
    'Trisplang LH': 357500,
    'Side Roof LH': 357500,
    'Roof': 1001000,
    'Cover': 286000,
  };

  static const List<String> validPanelNames = [
    'Bumper Depan', 'Spoiler Bumper depan', 'Kap Mesin', 'Bumper Belakang', 
    'Spoiler Bumper Belakang', 'Bagasi', 'Spoiler Bagasi', 'Fender RH', 
    'Pintu Depan RH', 'Spion RH', 'Pintu Belakang RH', 'Quarter RH', 
    'Trisplang RH', 'Side Roof RH', 'Fender LH', 'Pintu Depan LH', 
    'Spion LH', 'Pintu Belakang LH', 'Quarter LH', 'Trisplang LH', 
    'Side Roof LH', 'Roof', 'Cover'
  ];

  static double calculateCost(String panelName, String severity) {
    final basePrice = basePanelPrices[panelName] ?? 500000.0; // Fallback price
    double multiplier = 1.0;
    
    final normalizedSeverity = severity.toLowerCase();
    if (normalizedSeverity == 'sedang') {
      multiplier = 1.5;
    } else if (normalizedSeverity == 'berat') {
      multiplier = 2.0;
    }
    
    return basePrice * multiplier;
  }
}
