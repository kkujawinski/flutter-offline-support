import 'dart:convert' as convert;
import 'package:http/http.dart' as http;

import 'package:offline_support/models.dart';

final String apiServer = 'http://127.0.0.1:5000';

class ProductsService {
  Future<List<Product>> getAll() async {
    var productsListJson = await fetchList();
    return productsListJson
        .map<Product>(
          (json) => Product.fromJson(json),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchList() async {
    var response = await http.get(apiServer + '/products');
    if (response.statusCode == 200) {
      var converted = convert.jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(converted);
    }
    throw 'Incorrect statusCode: ${response.statusCode}';
  }
}
