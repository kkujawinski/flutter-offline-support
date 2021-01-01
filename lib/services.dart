import 'dart:convert' as convert;
import 'package:http/http.dart' as http;

import 'package:offline_support/models.dart';
import 'package:offline_support/offline.dart';

final String apiScheme = 'http';
final String apiHost = '127.0.0.1';
final int apiPort = 5000;
final String apiPath = '';

class DataService {
  OfflineController productOfflineController = OfflineController<Product>(
    'products',
    objectFactory: Product.fromJson,
    keyFunction: (item) => item['id'],
  );

  Future init() async {
    await productOfflineController.init();
  }

  Stream<Snapshot<List<Product>>> getProducts({String nameContains}) async* {
    if (nameContains == null) {
      yield* productOfflineController.getOnlineList(
        listFetcher: fetchProductList,
        dropMissing: true,
      );
    } else {
      nameContains = nameContains.toLowerCase();
      yield* productOfflineController.getOnlineList(
        listFetcher: () => fetchProductList(nameContains: nameContains),
        condition: (item) => item['name'].toLowerCase().contains(nameContains),
        dropMissing: false,
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchProductList({String nameContains}) async {
    try {
      var uri = Uri(
        scheme: apiScheme,
        host: apiHost,
        port: apiPort,
        path: apiPath + '/products',
        queryParameters: {
          if (nameContains != null) 'name': nameContains,
        },
      );
      print('GET $uri');
      var response = await http.get(uri);
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
