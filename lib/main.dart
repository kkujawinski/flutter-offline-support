import 'package:flutter/material.dart';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:offline_support/models.dart';
import 'package:offline_support/offline.dart';
import 'package:offline_support/services.dart';

class Globals {
  static DataService dataService = DataService();
}

void main() async {
  await Hive.initFlutter();
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
  String loadingStatus;

  @override
  void initState() {
    super.initState();
    initLoadData();
  }

  Future initLoadData() async {
    await Globals.dataService.init();
    await loadData();
  }

  Future loadData() async {
    setState(() {
      loadingStatus = 'LOADING';
    });
    await Future.delayed(Duration(seconds: 1));

    Stream<Snapshot<List<Product>>> productsSnapshotStream = Globals.dataService.getProducts();

    await for (var productsSnapshot in productsSnapshotStream) {
      var products = productsSnapshot.data..sortByName();

      setState(() {
        this.products = products;
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
      appBar: AppBar(
        title: Text('Offline Support Example'),
      ),
      body: Padding(
          padding: EdgeInsets.all(5),
          child: this.products == null
              ? Center(
                  child: CircularProgressIndicator(),
                )
              : ListView.builder(
                  itemCount: this.products.length,
                  itemBuilder: (BuildContext context, int index) {
                    Product product = products[index];
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text('Category: ${product.categoryId.substring(0, 9)}...\n'
                          'Generated: ${product.generated}'),
                    );
                  },
                )),
      floatingActionButton: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text('Status $loadingStatus'),
          FloatingActionButton(
            onPressed: () {
              products = null;
              loadData();
            },
            tooltip: 'Reload',
            child: Icon(Icons.refresh),
          ),
        ],
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
