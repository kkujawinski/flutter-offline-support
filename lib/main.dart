import 'package:flutter/material.dart';
import 'package:offline_support/models.dart';
import 'package:offline_support/services.dart';

void main() {
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
  ProductsService productsService = ProductsService();

  @override
  _ProductsListState createState() => _ProductsListState();
}

class _ProductsListState extends State<ProductsList> {
  List<Product> products;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future loadData() async {
    await Future.delayed(Duration(seconds: 1));
    var products = await widget.productsService.getAll()
      ..sortByName();
    setState(() {
      this.products = products;
    });
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
                      subtitle: Text('Category: ${product.categoryId.substring(0, 9)}...'),
                    );
                  },
                )),
      floatingActionButton: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton(
            onPressed: () {
              setState(() {
                products = null;
              });
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
