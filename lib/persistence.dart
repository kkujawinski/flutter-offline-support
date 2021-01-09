import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:uuid/uuid.dart';

typedef Persistor = Future<Map<String, dynamic>> Function(Map<String, dynamic> json);
typedef OutputConverter<T> = T Function(Map<String, dynamic> json);
typedef PersistenceCallback<T> = Function(T saved, PersistenceError error);
typedef PersistenceCallbackCondition<T> = bool Function(String persistenceId, Map<String, dynamic> request);

abstract class Persistable {
  Map<String, dynamic> toJson();
}

class PersistorDefinition<T> {
  final Persistor persistor;
  final OutputConverter<T> outputConverter;

  Map<String, PersistenceCallbackDefinition> _registeredCallbacks = {};

  PersistorDefinition(this.persistor, this.outputConverter);

  String registerCallback(PersistenceCallbackDefinition<T> persistenceCallbackDefinition) {
    var callbackId = Uuid().v4();
    _registeredCallbacks[callbackId] = persistenceCallbackDefinition;
    return callbackId;
  }

  void callCallbacks(T saved, PersistenceError error) {
    _registeredCallbacks.entries.forEach((entry) {
      var persistenceCallbackDefinition = entry.value as PersistenceCallbackDefinition<T>;
      if (persistenceCallbackDefinition.callOnce && persistenceCallbackDefinition.executed) {
        return;
      }
      persistenceCallbackDefinition.callback(saved, error);
      persistenceCallbackDefinition.executed = true;
    });
    _registeredCallbacks.removeWhere((key, value) => value.callOnce && value.executed);
  }
}

class PersistenceCallbackDefinition<T> {
  final PersistenceCallback<T> callback;
  final PersistenceCallbackCondition<T> condition;
  final bool callOnce;

  bool executed = false;

  PersistenceCallbackDefinition(this.callback, {this.condition, this.callOnce = false});
}

class PersistenceError implements Exception {
  final String message;
  final Response failedResponse;
  final Map<String, dynamic> failedResponseData;
  final Exception originException;

  PersistenceError(this.message, {this.failedResponse, this.failedResponseData, this.originException});

  String toStringInner() {
    if (failedResponse != null) {
      return '${failedResponse.statusCode} - ${failedResponse.request.url.path}';
    } else {
      return originException.toString();
    }
  }

  String toString() => 'PersistenceError ${toStringInner()}';
}

class PersistenceRequestError extends PersistenceError {
  PersistenceRequestError(
    String message, {
    Response failedResponse,
    Map<String, dynamic> failedResponseData,
    Exception originException,
  }) : super(
          message,
          failedResponse: failedResponse,
          failedResponseData: failedResponseData,
          originException: originException,
        );

  String toString() => 'PersistenceRequestError ${toStringInner()}';
}

class PersistenceExecutionResults {
  final bool shouldRetry;
  final PersistenceError exception;
  final Map<String, dynamic> data;

  PersistenceExecutionResults({
    this.shouldRetry,
    this.exception,
    this.data,
  });
}

class PersistenceController {
  static const String PERSISTENCE_BOX_NAME = '_persistence';
  static PersistenceController _instance;

  Box _box;
  Map<String, PersistorDefinition> _registeredPersistors = {};

  bool _initialized = false;

  static PersistenceController getInstance() {
    if (_instance == null) {
      _instance = PersistenceController();
    }
    return _instance;
  }

  init() async {
    if (_initialized) return;
    _box = await Hive.openBox(PERSISTENCE_BOX_NAME);
    _initialized = true;

    _reexecutePending();
  }

  registerPersistors(Map<String, PersistorDefinition> persistors) {
    assert(
      _registeredPersistors.keys.toSet().intersection(persistors.keys.toSet()).isEmpty,
      'Some of persistors ids where already registered',
    );
    assert(
      !_initialized,
      'Can\'t register new persistors after controller initialization',
    );
    _registeredPersistors.addAll(persistors);
  }

  persist<T extends Persistable>(String persistorId, T object, {PersistenceCallback<T> callback}) {
    assert(_initialized);
    assert(_registeredPersistors.containsKey(persistorId));

    String persistenceId = Uuid().v4();
    _box.put(
      persistenceId,
      {
        'persistenceId': persistenceId,
        'persistorId': persistorId,
        'body': object.toJson(),
        'created': DateTime.now().toIso8601String(),
      },
    );

    if (callback != null) {
      registerCallback(
        persistorId,
        PersistenceCallbackDefinition<T>(
          callback,
          callOnce: true,
          condition: (_persistenceId, request) => _persistenceId == persistenceId,
        ),
      );
    }
    execute<T>(persistenceId);
  }

  Future execute<T>(String persistenceId) async {
    var intervals = [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 15)];

    var item = _box.get(persistenceId);
    var body = Map<String, dynamic>.from(item['body']);
    var persistorId = item['persistorId'];
    var persistorDefinition = _registeredPersistors[persistorId];

    print('Persisting $persistorId (id=$persistenceId)');
    while (true) {
      var inverval = intervals.length > 1 ? intervals.removeAt(0) : intervals[0];

      PersistenceExecutionResults executionResults = await _execute(persistorDefinition.persistor, body);

      if (!executionResults.shouldRetry) {
        _box.delete(persistenceId);
        var success;
        if (executionResults.data != null) {
          success = persistorDefinition.outputConverter(executionResults.data);
          print('Persisting $persistorId (id=$persistenceId) succeeded');
        } else {
          print('Persisting $persistorId (id=$persistenceId) failed. Error ${executionResults.exception}');
        }
        persistorDefinition.callCallbacks(success, executionResults.exception);
        break;
      } else {
        print('Persisting $persistorId (id=$persistenceId) failed. '
            'Error: ${executionResults.exception}. '
            'Retrying after $inverval');
        await Future.delayed(inverval);
      }
    }
  }

  Future<PersistenceExecutionResults> _execute(Persistor persistor, Map<String, dynamic> body) async {
    try {
      var data = await persistor(body);
      return PersistenceExecutionResults(shouldRetry: false, data: data);
    } on PersistenceRequestError catch (exception) {
      return PersistenceExecutionResults(
        shouldRetry: false,
        exception: exception,
      );
    } on PersistenceError catch (exception) {
      return PersistenceExecutionResults(
        shouldRetry: true,
        exception: exception,
      );
    }
  }

  _reexecutePending() {
    var restartItems = _box.values.map(
      (item) => item['persistenceId'],
    );
    restartItems.forEach((persistenceId) {
      execute(persistenceId);
    });
  }

  String registerCallback<T>(String persistorId, PersistenceCallbackDefinition<T> persistenceCallbackDefinition) {
    return _registeredPersistors[persistorId].registerCallback(persistenceCallbackDefinition);
  }
}
