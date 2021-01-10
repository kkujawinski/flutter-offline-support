import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:offline_support/models.dart';
import 'package:offline_support/offline.dart';
import 'package:offline_support/persistence.dart';
import 'package:offline_support/services.dart';

class Globals {
  static DataService dataService = DataService(PersistenceController.getInstance());
  static PersistenceController persistenceController = PersistenceController.getInstance();
  static GlobalKey appGlobalKey = GlobalKey();
}

void main() async {
  await Hive.initFlutter();
  await Globals.dataService.init();
  await Globals.persistenceController.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline support in Flutter application',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: ProductsList(),
    );
  }
}

class ProductsList extends StatefulWidget {
  @override
  _ProductsListState createState() => _ProductsListState();
}

class _ProductsListState extends State<ProductsList> {
  List<Product> products;
  List<ProductCategory> categories;
  String loadingStatus;
  bool newProductDialogOpen = false;

  TextEditingController textController;

  @override
  void initState() {
    super.initState();
    initLoadData();
    textController = TextEditingController();
  }

  Future initLoadData() async {
    await loadData();
    Globals.persistenceController.registerCallback<Product>(
      DataService.SAVE_PRODUCT_PERSISTOR_ID,
      PersistenceCallbackDefinition<Product>(
        (Product saved, PersistenceError error) {
          if (saved != null) {
            if (!newProductDialogOpen) {
              var scaffoldState = (Globals.appGlobalKey.currentState as ScaffoldState);
              scaffoldState.showSnackBar(
                SnackBar(
                  content: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('Saved ${saved.name}'),
                  ),
                ),
              );
            }
            loadData();
          } else {
            if (!newProductDialogOpen) {
              var scaffoldState = (Globals.appGlobalKey.currentState as ScaffoldState);
              scaffoldState.showSnackBar(
                SnackBar(
                  backgroundColor: Colors.redAccent[700],
                  content: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(error.message),
                  ),
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future loadData({String nameContains}) async {
    setState(() {
      loadingStatus = 'LOADING';
    });

    if (categories == null) {
      Stream<Snapshot<List<ProductCategory>>> categoriesSnapshotStream = Globals.dataService.getCategories();
      await for (var categoriesSnapshot in categoriesSnapshotStream) {
        setState(() {
          categories = categoriesSnapshot.data;
        });
      }
    }

    Stream<Snapshot<List<Product>>> productsSnapshotStream = Globals.dataService.getProducts(
      nameContains: nameContains,
      prefetchCategories: true,
    );

    await for (var productsSnapshot in productsSnapshotStream) {
      setState(() {
        this.products = productsSnapshot.data..sortByName();
        if (productsSnapshot.returnedType == SnapshotType.ONLINE) {
          loadingStatus = 'ONLINE DATA';
        } else if (productsSnapshot.returnedType == SnapshotType.OFFLINE &&
            productsSnapshot.requestedType == SnapshotType.ONLINE) {
          loadingStatus = 'OFFLINE DATA\n(failed reloading)';
        } else {
          loadingStatus = 'OFFLINE DATA';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Globals.appGlobalKey,
      appBar: AppBar(
        title: Text('Offline Support Example'),
      ),
      body: Padding(
        padding: EdgeInsets.all(5),
        child: Column(
          children: [
            ListTile(
              title: TextField(
                controller: textController,
                decoration: InputDecoration(
                  hintText: 'Filter product list',
                ),
              ),
              trailing: Container(
                color: Colors.blue,
                child: FlatButton(
                  child: Icon(
                    Icons.search,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    products = null;
                    loadData(nameContains: textController.text);
                  },
                ),
              ),
            ),
            this.products == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 25.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: this.products.length,
                    itemBuilder: (BuildContext context, int index) {
                      Product product = products[index];
                      ProductCategory category = product?.category?.data;
                      return ListTile(
                        title: Text('${product.name} (${product.generated ?? ''}${product.isLocal ? 'local' : ''})'),
                        subtitle: Text('${category?.name} (${category?.generated})'),
                      );
                    },
                  ),
          ],
        ),
      ),
      floatingActionButton: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 150,
              child: Text('Status $loadingStatus', textAlign: TextAlign.center),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: FloatingActionButton(
              onPressed: () {
                products = null;
                textController.text = '';
                loadData();
              },
              tooltip: 'Reload',
              child: Icon(Icons.refresh),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: FloatingActionButton(
              onPressed: (categories?.isNotEmpty ?? false)
                  ? () async {
                      newProductDialogOpen = true;
                      await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return CreateProductForm(
                            categories: categories,
                            productSaved: () {
                              loadData();
                            },
                          );
                        },
                      );
                      newProductDialogOpen = false;
                    }
                  : () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            content: Text('Categories not loaded'),
                          );
                        },
                      );
                    },
              tooltip: 'Add new',
              child: Icon(Icons.add),
            ),
          )
        ],
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class CreateProductForm extends StatefulWidget {
  final List<ProductCategory> categories;
  final Function() productSaved;

  const CreateProductForm({Key key, this.categories, this.productSaved}) : super(key: key);

  @override
  _CreateProductFormState createState() => _CreateProductFormState();
}

class _CreateProductFormState extends State<CreateProductForm> {
  final _formKey = GlobalKey<FormState>();

  String _productNameError;

  ProductCategory _category;
  String _productName;

  bool _widgetDisposed = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(8.0),
              child: TextFormField(
                onChanged: (String value) {
                  setState(() {
                    _productNameError = null;
                  });
                },
                onSaved: (String value) {
                  _productName = value;
                },
                validator: (String value) {
                  return value.trim().length == 0 ? 'Product name can\'t be empty' : null;
                },
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  helperText: 'Product name',
                  errorText: _productNameError != null ? _productNameError : null,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: DropdownButtonFormField<ProductCategory>(
                onSaved: (ProductCategory value) {
                  _category = value;
                },
                onChanged: (ProductCategory value) {}, // required
                value: widget.categories.first,
                items: widget.categories
                    .map(
                      (item) => DropdownMenuItem<ProductCategory>(
                        value: item,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                decoration: InputDecoration(
                  helperText: 'Category',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: RaisedButton(
                child: Text("Save"),
                onPressed: () {
                  if (_formKey.currentState.validate()) {
                    _formKey.currentState.save();
                    setState(() {
                      _saving = true;
                    });
                    Globals.dataService.saveProduct(
                      Product(
                        name: _productName,
                        categoryId: _category.id,
                      ),
                      callback: (Product saved, PersistenceError error) {
                        if (_widgetDisposed) return;
                        if (saved != null) {
                          Navigator.of(context).pop();
                          var scaffoldState = (Globals.appGlobalKey.currentState as ScaffoldState);
                          scaffoldState.showSnackBar(
                            SnackBar(
                              content: Padding(
                                padding: EdgeInsets.all(10),
                                child: Text("Saved ${saved.name}"),
                              ),
                            ),
                          );
                        } else if (error.originException != null) {
                          Navigator.of(context).pop();
                          var scaffoldState = (Globals.appGlobalKey.currentState as ScaffoldState);
                          scaffoldState.showSnackBar(
                            SnackBar(
                              content: Padding(
                                padding: EdgeInsets.all(10),
                                child: Text(error.originException.toString()),
                              ),
                            ),
                          );
                        } else if (error.failedResponseData != null) {
                          if (error.failedResponseData['name'] != null) {
                            setState(() {
                              _saving = false;
                              _productNameError = error.failedResponseData['name'];
                            });
                          }
                        }
                      },
                    );
                    if (widget.productSaved != null) {
                      widget.productSaved();
                    }
                  }
                },
              ),
            ),
            _saving
                ? SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(),
                  )
                : SizedBox(height: 4)
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _widgetDisposed = true;
    super.dispose();
  }
}
