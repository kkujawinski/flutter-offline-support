from datetime import datetime

from flask import jsonify, Flask, request
from tinydb import TinyDB, Query
import pathlib


app = Flask(__name__)
db = TinyDB(pathlib.Path().absolute().joinpath('db.json'))
db_products = db.table('products')
db_categories = db.table('categories')

@app.route('/')
def index():
    return 'api-ok'


@app.route('/products', methods=['GET', 'POST'])
def products():
    if request.method == 'GET':
        output = db_products.all()

        name_filter = request.args.get('name')
        if name_filter is not None:
            output = filter(lambda item: name_filter in item['name'].lower(), output)

        output = [dict(item, generated=datetime.now().isoformat())
                  for item in output]
        return jsonify(output)
    elif request.method == 'POST':
        product = request.get_json(force=True);

        if product['name'] in map(lambda item: item['name'], db_products.all()):
            return jsonify({'name': 'Product already exists'}), 400

        db_products.insert(product)

        return jsonify(dict(product, generated=datetime.now().isoformat()))


@app.route('/categories')
def categories():
    output = db_categories.all()

    ids_filter = request.args.get('ids')
    if ids_filter is not None:
        ids = set(ids_filter.split(','))
        output = filter(lambda item: item['id'] in ids, output)

    output = [dict(item, generated=datetime.now().isoformat()) for item in output]
    return jsonify(output)


def init_database():
    default_categories = [
        {'name': 'Vegetables', 'id': 'f4f986a3-748b-4636-8128-91a92fa4988a'},
        {'name': 'Fruits', 'id': 'd899d6f8-7e17-4bd1-8523-37855f5561a2'},
    ]
    default_products = [
        {'name': 'Tomato', 'category_id': 'f4f986a3-748b-4636-8128-91a92fa4988a', 'id': '160d4671-d47b-42ef-82f3-9028fed9394a'},
        {'name': 'Potato', 'category_id': 'f4f986a3-748b-4636-8128-91a92fa4988a', 'id': '3a2f59ed-1107-4f34-9474-c8a8cab1161d'},
        {'name': 'Apple', 'category_id': 'd899d6f8-7e17-4bd1-8523-37855f5561a2', 'id': 'a9768857-f210-4b23-9c66-967930a22645'},
        {'name': 'Banana', 'category_id': 'd899d6f8-7e17-4bd1-8523-37855f5561a2', 'id': '75f1ac84-6708-4db6-9a7a-b7d3db3062fb'}
    ]
    for category in default_categories:
        if db_categories.search(Query().name == category['name']):
            continue
        db_categories.insert(category)
        print('Inserted category %s' % category)
    for product in default_products:
        if db_products.search(Query().name == product['name']):
            continue
        db_products.insert(product)
        print('Inserted product %s' % product)


if __name__ == '__main__':
    init_database()
    app.run()
