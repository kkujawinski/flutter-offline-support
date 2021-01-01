class Product {
  final String id;
  final String name;
  final String categoryId;
  final DateTime generated;

  Product({
    this.id,
    this.name,
    this.categoryId,
    this.generated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'name': this.name,
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
