import 'dart:convert' as convert;
import 'package:http/http.dart' as http;

import 'package:offline_support/models.dart';
import 'package:offline_support/offline.dart';

final String apiServer = 'http://127.0.0.1:5000';

class DataService {
  OfflineController productOfflineController = OfflineController<Product>(
    'products',
    objectFactory: Product.fromJson,
    keyFunction: (item) => item['id'],
  );

  Future init() async {
    await productOfflineController.init();
  }

  Stream<Snapshot<List<Product>>> getProducts() async* {
    yield* productOfflineController.getOnlineList(
      listFetcher: fetchProductList,
    );
  }

  Future<List<Map<String, dynamic>>> fetchProductList() async {
    try {
      var response = await http.get(apiServer + '/products');
      if (response.statusCode == 200) {
        var converted = convert.jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(converted);
      }
      throw FailedOnlineRequest(failedResponse: response);
    } catch (exception) {
      throw FailedOnlineRequest(originException: exception);
    }
  }
}
