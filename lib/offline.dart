import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:offline_support/persistence.dart';

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

  Snapshot<Q> copy<Q>({Q data}) {
    return Snapshot<Q>(
      requestedType: this.requestedType,
      returnedType: this.returnedType,
      data: data,
      failedResponse: this.failedResponse,
      originException: this.originException,
    );
  }
}

class OfflineController<T> {
  static const String VERSIONS_BOX_NAME = '_versions';

  static bool _globalInitialized = false;
  static Box _versionsBox;

  static Set<String> _restrictedBoxNames = {};

  final String boxName;
  final ObjectFactory<T> objectFactory;
  final KeyFunction keyFunction;
  final String version;
  Box box;

  bool _initialized = false;

  OfflineController(
    this.boxName, {
    @required this.objectFactory,
    @required this.keyFunction,
    this.version = '',
  }) {
    assert(!_restrictedBoxNames.contains(boxName));
    _restrictedBoxNames.add(boxName);
  }

  Future init() async {
    await OfflineController._globalInit();
    box = await Hive.openBox(this.boxName);
    _boxVersionCheck();
    this._initialized = true;
  }

  static Future _globalInit() async {
    if (_globalInitialized) return;
    _versionsBox = await Hive.openBox(VERSIONS_BOX_NAME);
    _globalInitialized = true;
  }

  storeLocal<Q extends Persistable>(Q object) {
    var productJson = object.toJson();
    var key = keyFunction(productJson);
    box.put(key, {'data': productJson, 'key': key, 'is_local': true});
  }

  Stream<Snapshot<List<T>>> getList({
    ListFetcher listFetcher,
    bool dropMissing: false,
    WhereConditionTest condition,
    bool skipOffline,
    bool skipOnline,
  }) async* {
    assert(this._initialized);

    // Returning locally stored offline results
    Iterable<Map<String, dynamic>> offlineItems = box.values.map((e) => Map<String, dynamic>.from(e));
    offlineItems = _applyWhereCondition(offlineItems, condition);

    if (skipOffline != true) {
      yield Snapshot<List<T>>(
        requestedType: SnapshotType.OFFLINE,
        returnedType: SnapshotType.OFFLINE,
        data: _prepareObjectsList(offlineItems).toList(),
      );
    }

    if (skipOnline != true) {
      // Making a call for online results
      try {
        List<Map<String, dynamic>> onlineItems = await listFetcher();
        _storeItems(onlineItems, dropMissing: dropMissing);
      } on FailedOnlineRequest catch (exception) {
        // Returning again offline results with failure information
        yield Snapshot<List<T>>(
          requestedType: SnapshotType.ONLINE,
          returnedType: SnapshotType.OFFLINE,
          data: _prepareObjectsList(offlineItems).toList(),
          failedResponse: exception.failedResponse,
          originException: exception.originException,
        );
        return;
      }

      Iterable<Map<String, dynamic>> finalItems = box.values.map((e) => Map<String, dynamic>.from(e));
      finalItems = _applyWhereCondition(finalItems, condition);

      // Returning online results
      yield Snapshot<List<T>>(
        requestedType: SnapshotType.ONLINE,
        returnedType: SnapshotType.ONLINE,
        data: _prepareObjectsList(finalItems).toList(),
      );
    }
  }

  Iterable<T> _prepareObjectsList(Iterable<Map<String, dynamic>> items) sync* {
    for (var item in items) {
      var object = objectFactory(Map<String, dynamic>.from(item['data']));
      if (object is Persistable) {
        (object as Persistable).isLocal = item['is_local'] ?? false;
      }
      yield object;
    }
  }

  Iterable<Map<String, dynamic>> _applyWhereCondition(Iterable<Map<String, dynamic>> items, WhereConditionTest where) {
    if (where != null) {
      items = items.where((item) => where(Map<String, dynamic>.from(item['data'])));
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

  _boxVersionCheck() {
    if ((_versionsBox.get(boxName) ?? '') != version) {
      print('Clearing box $boxName. Versions mismatch ${_versionsBox.get(boxName) ?? ''} vs $version');
      box.deleteAll(box.keys);
      _versionsBox.put(boxName, version);
    }
  }
}
