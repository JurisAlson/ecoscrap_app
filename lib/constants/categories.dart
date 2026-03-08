const List<String> kMajorCategories = [
  "PP WHITE",
  "HDPE",
  "BLACK",
  "PP COLORED",
  "PET",
];

const List<String> kBuySubCategories = [
  "PLASTIC BOTTLE",
  "TUPPERWARE",
  "WATER GALLON",
  "MIXED PLASTICS",
  "CONTAINERS",
];

const Map<String, double> kFixedBuyCostPerKg = {
  "PP WHITE": 5.0,
  "HDPE": 8.0,
  "BLACK": 3.0,
  "PP COLORED": 6.0,
  "PET": 4.0,
};

const Map<String, double> kFixedSellPricePerKg = {
  "PP WHITE": 10.0,
  "HDPE": 15.0,
  "BLACK": 6.0,
  "PP COLORED": 12.0,
  "PET": 8.0,
};

String normalizeCategoryKey(String raw) {
  final v = raw
      .trim()
      .toUpperCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  const exactAliases = <String, String>{
    'PP WHITE': 'PP WHITE',
    'PPWHITE': 'PP WHITE',

    'PP COLORED': 'PP COLORED',
    'PP COLOR': 'PP COLORED',
    'PPCOLORED': 'PP COLORED',
    'COLORED PP': 'PP COLORED',

    'HDPE': 'HDPE',

    'PET': 'PET',
    'PETE': 'PET',
    'PET BOTTLE': 'PET',

    'BLACK': 'BLACK',
    'BLACK PLASTIC': 'BLACK',
  };

  if (exactAliases.containsKey(v)) {
    return exactAliases[v]!;
  }

  for (final entry in exactAliases.entries) {
    if (v.contains(entry.key)) {
      return entry.value;
    }
  }

  return v;
}

Map<String, double> emptyMajorCategoryMap() {
  return {for (final c in kMajorCategories) c: 0.0};
}