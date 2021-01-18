import 'dart:convert' as convert;
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:offline_support/models.dart';
import 'package:offline_support/offline.dart';
import 'package:offline_support/persistence.dart';

class DataService {
  OfflineController productOfflineController = OfflineController<Product>(
    'products',
    objectFactory: Product.fromJson,
    keyFunction: (item) => item['id'],
    version: '20210110-1',
  );
  OfflineController categoriesOfflineController = OfflineController<ProductCategory>(
    'categories',
    objectFactory: ProductCategory.fromJson,
    keyFunction: (item) => item['id'],
    version: '20210102-1',
  );
  PersistenceController persistanceController;

  static const String SAVE_PRODUCT_PERSISTOR_ID = 'saveProductPersistor';

  DataService(this.persistanceController);

  Future init() async {
    await productOfflineController.init();
    await categoriesOfflineController.init();
    persistanceController.registerPersistors({
      SAVE_PRODUCT_PERSISTOR_ID: PersistorDefinition<Product>(saveProductPersistor, Product.fromJson),
    });
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
    var uri = HttpService.prepareUri('/products', queryParameters: {
      if (nameContains != null) 'name': nameContains,
    });
    var data = await HttpService.get(uri);
    return List<Map<String, dynamic>>.from(data);
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
    var uri = HttpService.prepareUri('/categories', queryParameters: {
      if (ids != null) 'ids': ids.join(','),
    });
    var data = await HttpService.get(uri);
    return List<Map<String, dynamic>>.from(data);
  }

  void saveProduct(Product product, {PersistenceCallback<Product> callback}) {
    persistanceController.persist<Product>(SAVE_PRODUCT_PERSISTOR_ID, product, callback: callback);
    productOfflineController.storeLocal(product);
  }

  void registerSaveProductCallback(
      PersistenceCallback<Product> callback, PersistenceCallbackCondition<Product> condition) {
    persistanceController.registerCallback<Product>(
      SAVE_PRODUCT_PERSISTOR_ID,
      PersistenceCallbackDefinition<Product>(callback, condition: condition),
    );
  }

  Future<Map<String, dynamic>> saveProductPersistor(Map<String, dynamic> product) {
    var uri = HttpService.prepareUri('/products');
    return HttpService.post(uri, product);
  }
}

class HttpService {
  static const String API_SCHEME = 'http';
  static const String API_HOST = '127.0.0.1';
  static const int API_PORT = 5000;
  static const String API_PATH = '';

  static Uri prepareUri(String path, {Map<String, String> queryParameters}) {
    return Uri(
      scheme: API_SCHEME,
      host: API_HOST,
      port: API_PORT,
      path: API_PATH + path,
      queryParameters: queryParameters,
    );
  }

  static Future<Map<String, dynamic>> post(Uri uri, Map<String, dynamic> data) async {
    try {
      print('POST $uri');
      var response = await http.post(uri, body: jsonEncode(data));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return convert.jsonDecode(response.body);
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        throw PersistenceRequestError(
          response.body.toString(),
          failedResponse: response,
          failedResponseData: convert.jsonDecode(response.body),
        );
      } else {
        throw PersistenceError(response.body.toString(), failedResponse: response);
      }
    } on PersistenceRequestError {
      rethrow;
    } catch (exception) {
      throw PersistenceError(exception.toString(), originException: exception);
    }
  }

  static Future<dynamic> get(Uri uri) async {
    try {
      print('GET $uri');
      var response = await http.get(uri);
      if (response.statusCode == 200) {
        return convert.jsonDecode(response.body);
      }
      throw FailedOnlineRequest(failedResponse: response);
    } catch (exception) {
      throw FailedOnlineRequest(originException: exception);
    }
  }
}
