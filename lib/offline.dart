import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';

class FailedOnlineRequest implements Exception {
  final Response failedResponse;
  final Exception originException;
  FailedOnlineRequest({this.failedResponse, this.originException});
}

typedef ListFetcher = Future<List<Map<String, dynamic>>> Function();
typedef KeyFunction = String Function(Map<String, dynamic> json);
typedef ObjectFactory<T> = T Function(Map<String, dynamic> json);
typedef WhereConditionTest = bool Function(Map<String, dynamic> json);

enum SnapshotType { OFFLINE, ONLINE }

class Snapshot<T> {
  final SnapshotType requestedType;
  final SnapshotType returnedType;
  final T data;
  final Response failedResponse;
  final Exception originException;

  Snapshot({
    this.requestedType,
    this.returnedType,
    this.data,
    this.failedResponse,
    this.originException,
  });
}

class OfflineController<T> {
  final String boxName;
  final ObjectFactory<T> objectFactory;
  final KeyFunction keyFunction;
  Box box;

  bool _initialized = false;

  OfflineController(
    this.boxName, {
    @required this.objectFactory,
    @required this.keyFunction,
  });

  Future init() async {
    box = await Hive.openBox(this.boxName);
    this._initialized = true;
  }

  Stream<Snapshot<List<T>>> getOnlineList({
    ListFetcher listFetcher,
    bool dropMissing: false,
    WhereConditionTest condition,
  }) async* {
    assert(this._initialized);

    Iterable<Map<String, dynamic>> offlineItems = box.values.map((item) => Map<String, dynamic>.from(item['data']));
    offlineItems = _applyWhereCondition(offlineItems, condition);
    yield Snapshot<List<T>>(
      requestedType: SnapshotType.OFFLINE,
      returnedType: SnapshotType.OFFLINE,
      data: _prepareObjectsList(offlineItems).toList(),
    );

    try {
      List<Map<String, dynamic>> onlineItems = await listFetcher();
      _storeItems(onlineItems, dropMissing: dropMissing);
    } on FailedOnlineRequest catch (exception) {
      yield Snapshot<List<T>>(
        requestedType: SnapshotType.ONLINE,
        returnedType: SnapshotType.OFFLINE,
        data: _prepareObjectsList(offlineItems).toList(),
        failedResponse: exception.failedResponse,
        originException: exception.originException,
      );
      return;
    }

    Iterable<Map<String, dynamic>> finalItems = box.values.map((item) => item['data']);
    finalItems = _applyWhereCondition(finalItems, condition);

    yield Snapshot<List<T>>(
      requestedType: SnapshotType.ONLINE,
      returnedType: SnapshotType.ONLINE,
      data: _prepareObjectsList(finalItems).toList(),
    );
  }

  Iterable<T> _prepareObjectsList(Iterable<Map<String, dynamic>> jsons) sync* {
    for (Map<String, dynamic> json in jsons) {
      yield objectFactory(json);
    }
  }

  Iterable<Map<String, dynamic>> _applyWhereCondition(Iterable<Map<String, dynamic>> items, WhereConditionTest where) {
    if (where != null) {
      items = items.where(where);
    }
    return items;
  }

  void _storeItems(Iterable<Map<String, dynamic>> items, {bool dropMissing: false}) {
    Set<String> oldKeys = Set<String>.from(box.keys);
    Set<String> newKeys = {};
    for (var item in items) {
      var key = keyFunction(item);
      box.put(key, {'data': item, 'key': key});
      newKeys.add(key);
    }
    if (dropMissing) {
      box.deleteAll(oldKeys.difference(newKeys));
    }
  }
}