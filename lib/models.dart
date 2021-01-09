import 'package:offline_support/offline.dart';
import 'package:offline_support/persistence.dart';
import 'package:uuid/uuid.dart';

class Product extends Persistable {
  String id;
  final String name;
  final String categoryId;
  final DateTime generated;

  // filled externally
  Snapshot<ProductCategory> category;

  Product({
    this.id,
    this.name,
    this.categoryId,
    this.generated,
  }) {
    if (id == null) {
      this.id = Uuid().v4();
//      this.isLocal = true;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'name': this.name,
      'category_id': this.categoryId,
      'generated': this.generated?.toIso8601String(),
    };
  }

  static Product fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      categoryId: json['category_id'],
      generated: DateTime.parse(json['generated']),
    );
  }
}

extension ListProductExtension on List<Product> {
  sortByName() => this.sort((a, b) => a.name.compareTo(b.name));
}

class ProductCategory {
  final String id;
  final String name;
  final DateTime generated;

  ProductCategory({
    this.id,
    this.name,
    this.generated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'name': this.name,
      'generated': this.generated.toIso8601String(),
    };
  }

  static ProductCategory fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: json['id'],
      name: json['name'],
      generated: DateTime.parse(json['generated']),
    );
  }
}
