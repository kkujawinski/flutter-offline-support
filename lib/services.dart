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
    version: '20210102-1',
  );
  OfflineController categoriesOfflineController = OfflineController<ProductCategory>(
    'categories',
    objectFactory: ProductCategory.fromJson,
    keyFunction: (item) => item['id'],
    version: '20210102-1',
  );

  Future init() async {
    await productOfflineController.init();
    await categoriesOfflineController.init();
  }

  Stream<Snapshot<List<Product>>> getProducts({String nameContains, prefetchCategories: false}) async* {
    Stream<Snapshot<List<Product>>> snapshotStream;
    if (nameContains == null) {
      snapshotStream = productOfflineController.getList(
        listFetcher: fetchProductList,
        dropMissing: true,
      );
    } else {
      nameContains = nameContains.toLowerCase();
      snapshotStream = productOfflineController.getList(
        listFetcher: () => fetchProductList(nameContains: nameContains),
        condition: (item) => item['name'].toLowerCase().contains(nameContains),
        dropMissing: false,
      );
    }
    await for (Snapshot<List<Product>> snapshot in snapshotStream) {
      await _prefetchProductsRelations(snapshot.data, snapshot.requestedType, prefetchCategories: prefetchCategories);
      yield snapshot;
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
      // Simulating long request
      await Future.delayed(Duration(seconds: 1));
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

  Future _prefetchProductsRelations(List<Product> items, SnapshotType prefetchType, {prefetchCategories: false}) async {
    if (prefetchCategories) {
      Set<String> categoriesIds = items.map((e) => e.categoryId).toSet();
      Snapshot<List<ProductCategory>> categoriesSnapshot = await getCategories(
        ids: categoriesIds,
        skipOffline: prefetchType != SnapshotType.OFFLINE,
        skipOnline: prefetchType != SnapshotType.ONLINE,
      ).first;
      Map<String, Snapshot<ProductCategory>> categoriesMap = Map.fromIterable(
        categoriesSnapshot.data,
        key: (item) => item.id,
        value: (item) => categoriesSnapshot.copy<ProductCategory>(data: item),
      );
      items.forEach((Product item) {
        item.category = categoriesMap[item.categoryId];
      });
    }
  }

  Stream<Snapshot<List<ProductCategory>>> getCategories({
    Set<String> ids,
    bool skipOffline,
    bool skipOnline,
  }) async* {
    if (ids == null) {
      yield* categoriesOfflineController.getList(
        listFetcher: fetchCategoriesList,
        dropMissing: true,
        skipOffline: skipOffline,
        skipOnline: skipOnline,
      );
    } else {
      yield* categoriesOfflineController.getList(
        listFetcher: () => fetchCategoriesList(ids: ids),
        condition: (item) => ids.contains(item['id']),
        dropMissing: false,
        skipOffline: skipOffline,
        skipOnline: skipOnline,
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchCategoriesList({Set<String> ids}) async {
    try {
      var uri = Uri(
        scheme: apiScheme,
        host: apiHost,
        port: apiPort,
        path: apiPath + '/categories',
        queryParameters: {
          if (ids != null) 'ids': ids.join(','),
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
