const List<String> kMajorCategories = [
  "PP WHITE",
  "PP TRANS",
  "PP COLOR",
  "HDPE",
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
  "HDPE": 13.0,
  "PP": 13.0,
  "PP WHITE": 13.0,
  "PP TRANS": 13.0,
  "PP COLOR": 13.0,
  "PET": 7.0,
};

const Map<String, double> kFixedSellPricePerKg = {
  "PP WHITE": 33.0,
  "PP TRANS": 42.0,
  "PP COLOR": 30.0,
  "PET": 23.0,
  "HDPE": 50.0,
  "PP": 30.0,
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
    'WHITE PP': 'PP WHITE',

    'PP TRANS': 'PP TRANS',
    'PPTRANs': 'PP TRANS',
    'PP TRANSPARENT': 'PP TRANS',
    'PP CLEAR': 'PP TRANS',
    'TRANS PP': 'PP TRANS',

    'PP COLOR': 'PP COLOR',
    'PP COLORED': 'PP COLOR',
    'PPCOLOR': 'PP COLOR',
    'PPCOLORED': 'PP COLOR',
    'COLORED PP': 'PP COLOR',
    'COLOR PP': 'PP COLOR',
    'BLACK': 'PP COLOR',
    'BLACK PLASTIC': 'PP COLOR',

    'PP': 'PP',

'HD': 'HDPE',
'HDPE': 'HDPE',

    'PET': 'PET',
    'PETE': 'PET',
    'PET BOTTLE': 'PET',
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