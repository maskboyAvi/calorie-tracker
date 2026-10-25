import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class FoodSearchService {
  Future<List<Food>> searchOpenFoodFacts(String query) async {
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '12',
      'fields': 'code,product_name,brands,serving_size,nutriments',
    });
    final response = await http
        .get(
          uri,
          headers: {'User-Agent': 'CalorieCompanion/1.0 (personal tracker)'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Food database unavailable (${response.statusCode}).');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['products'] is! List) return [];
    return (body['products'] as List)
        .whereType<Map<String, dynamic>>()
        .map((product) {
          final n = product['nutriments'] as Map<String, dynamic>? ?? {};
          double val(String key) => (n[key] as num?)?.toDouble() ?? 0;
          final name = (product['product_name'] as String?)?.trim() ?? '';
          if (name.isEmpty) return null;
          return Food(
            id: 'off-${product['code'] ?? name.hashCode}',
            name: name,
            serving: 100,
            unit: 'g',
            category: 'Packaged food',
            source: 'Open Food Facts',
            nutrition: Nutrition(
              kcal: val('energy-kcal_100g'),
              protein: val('proteins_100g'),
              carbs: val('carbohydrates_100g'),
              fat: val('fat_100g'),
            ),
          );
        })
        .whereType<Food>()
        .toList();
  }
}
