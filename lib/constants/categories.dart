// lib/constants/categories.dart

/// Your 4 major categories (FINAL list)
const List<String> kMajorCategories = [
  "PP WHITE",
  "HDPE",
  "BLACK",
  "PP COLORED",
];

/// Optional: subcategories (if you use these for BUY)
const List<String> kBuySubCategories = [
  "PLASTIC BOTTLE",
  "TUPPERWARE",
  "WATER GALLON",
  "MIXED PLASTICS",
  "CONTAINERS",
];

/// ✅ FIXED BUY COST per KG (edit values)
const Map<String, double> kFixedBuyCostPerKg = {
  "PP WHITE": 5.0,
  "HDPE": 8.0,
  "BLACK": 3.0,
  "PP COLORED": 6.0,
};

/// ✅ FIXED SELL PRICE per KG (edit values)
const Map<String, double> kFixedSellPricePerKg = {
  "PP WHITE": 10.0,
  "HDPE": 15.0,
  "BLACK": 6.0,
  "PP COLORED": 12.0,
};