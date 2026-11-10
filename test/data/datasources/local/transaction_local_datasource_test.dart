import 'package:flutter_pos/core/services/database/database_config.dart';
import 'package:flutter_pos/core/services/database/database_service.dart';
import 'package:flutter_pos/data/datasources/local/transaction_local_datasource_impl.dart';
import 'package:flutter_pos/data/models/ordered_product_model.dart';
import 'package:flutter_pos/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseService appDatabase;
  late TransactionLocalDatasourceImpl datasource;
  late Database testDatabase;

  const userId = 'user123';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDatabase = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );

    appDatabase = DatabaseService.instance;

    await appDatabase.initTestDatabase(
      testDatabase: testDatabase,
    );

    await testDatabase.insert(
      DatabaseConfig.userTableName,
      {'id': userId},
    );

    datasource = TransactionLocalDatasourceImpl(appDatabase);
  });

  tearDown(() async {
    await testDatabase.close();
  });

  Future<void> createSampleProduct({
    int id = 1,
    int stock = 50,
    int sold = 10,
  }) async {
    await testDatabase.insert(
      DatabaseConfig.productTableName,
      {
        'id': id,
        'createdById': userId,
        'name': 'Sample Product',
        'imageUrl': '',
        'stock': stock,
        'sold': sold,
        'price': 42,
        'description': '',
      },
    );
  }

  Future<Map<String, Object?>> readProduct(int id) async {
    final rows = await testDatabase.query(
      DatabaseConfig.productTableName,
      where: 'id = ?',
      whereArgs: [id],
    );

    return rows.first;
  }

  TransactionModel createSampleTransaction({
    int id = 1,
    String createdById = userId,
    int totalAmount = 1,
    int quantity = 1,
    int productId = 1,
  }) {
    return TransactionModel(
      id: id,
      createdById: createdById,
      paymentMethod: 'Cash',
      receivedAmount: totalAmount,
      returnAmount: 0,
      totalAmount: totalAmount,
      totalOrderedProduct: 1,
      orderedProducts: [
        OrderedProductModel(
          id: id,
          transactionId: id,
          productId: productId,
          quantity: quantity,
          stock: 1,
          name: 'Sample Product',
          imageUrl: '',
          price: totalAmount,
        ),
      ],
    );
  }

  group('TransactionLocalDatasourceImpl', () {
    group('createTransaction', () {
      test('inserts a transaction successfully', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();
        final result = await datasource.createTransaction(transaction);

        expect(result.isSuccess, isTrue);
        expect(result.data, transaction.id);
      });

      test('creates multiple transactions successfully', () async {
        await createSampleProduct();

        final first = await datasource.createTransaction(
          createSampleTransaction(id: 1),
        );

        final second = await datasource.createTransaction(
          createSampleTransaction(id: 2),
        );

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);

        final rows = await testDatabase.query(
          DatabaseConfig.transactionTableName,
        );

        expect(rows.length, 2);
      });

      test('stores ordered products with the transaction', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final result = await datasource.getTransaction(transaction.id);

        expect(result.data?.orderedProducts, isNotEmpty);
        expect(result.data?.orderedProducts?.length, 1);
        expect(result.data?.orderedProducts?.first.productId, 1);
      });

      test('deducts stock and increases sold quantity', () async {
        await createSampleProduct();

        final result = await datasource.createTransaction(
          createSampleTransaction(quantity: 1),
        );

        final product = await readProduct(1);

        expect(result.isSuccess, isTrue);
        expect(product['stock'], 49);
        expect(product['sold'], 11);
      });

      test('rejects a sale when stock is insufficient', () async {
        await createSampleProduct(stock: 0);

        final result = await datasource.createTransaction(
          createSampleTransaction(quantity: 1),
        );

        final product = await readProduct(1);

        expect(result.isFailure, isTrue);
        expect(product['stock'], 0);
        expect(product['sold'], 10);

        final sales = await testDatabase.query(
          DatabaseConfig.transactionTableName,
        );

        expect(sales, isEmpty);
      });

      test('rejects a sale for a nonexistent product', () async {
        final result = await datasource.createTransaction(
          createSampleTransaction(productId: 999),
        );

        expect(result.isFailure, isTrue);
      });

      test('rejects duplicate transaction IDs without deducting stock twice',
          () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        final first = await datasource.createTransaction(transaction);
        final second = await datasource.createTransaction(transaction);

        final product = await readProduct(1);

        expect(first.isSuccess, isTrue);
        expect(second.isFailure, isTrue);
        expect(product['stock'], 49);
        expect(product['sold'], 11);
      });

      test('rejects zero quantity', () async {
        await createSampleProduct();

        final result = await datasource.createTransaction(
          createSampleTransaction(quantity: 0),
        );

        expect(result.isFailure, isTrue);

        final product = await readProduct(1);
        expect(product['stock'], 50);
      });
    });

    group('updateTransaction', () {
      test('updates an existing transaction', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final updated = createSampleTransaction(
          id: transaction.id,
          totalAmount: 100,
        );

        final result = await datasource.updateTransaction(updated);

        expect(result.isSuccess, isTrue);

        final retrieved = await datasource.getTransaction(transaction.id);

        expect(retrieved.data?.totalAmount, 100);
      });

      test('does not deduct stock twice when editing the same quantity',
          () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final updated = createSampleTransaction(
          id: transaction.id,
          quantity: 1,
          totalAmount: 100,
        );

        final result = await datasource.updateTransaction(updated);
        final product = await readProduct(1);

        expect(result.isSuccess, isTrue);
        expect(product['stock'], 49);
        expect(product['sold'], 11);
      });

      test('correctly applies a revised quantity', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction(quantity: 1);

        await datasource.createTransaction(transaction);

        final updated = createSampleTransaction(
          id: transaction.id,
          quantity: 2,
          totalAmount: 84,
        );

        final result = await datasource.updateTransaction(updated);
        final product = await readProduct(1);

        expect(result.isSuccess, isTrue);
        expect(product['stock'], 48);
        expect(product['sold'], 12);
      });

      test('rejects editing a nonexistent transaction', () async {
        await createSampleProduct();

        final result = await datasource.updateTransaction(
          createSampleTransaction(id: 999),
        );

        expect(result.isFailure, isTrue);

        final product = await readProduct(1);
        expect(product['stock'], 50);
      });
    });

    group('getTransaction', () {
      test('retrieves an existing transaction', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final result = await datasource.getTransaction(transaction.id);

        expect(result.data, isNotNull);
        expect(result.data?.id, transaction.id);
        expect(result.data?.createdById, userId);
        expect(result.data?.paymentMethod, 'Cash');
        expect(result.data?.totalAmount, transaction.totalAmount);
      });

      test('returns null for a nonexistent transaction', () async {
        final result = await datasource.getTransaction(999);

        expect(result.data, isNull);
      });

      test('retrieves transaction with ordered products', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final result = await datasource.getTransaction(transaction.id);

        expect(result.data?.orderedProducts, isNotEmpty);
        expect(result.data?.totalOrderedProduct, 1);
      });
    });

    group('getAllUserTransactions', () {
      test('retrieves all transactions belonging to a user', () async {
        await createSampleProduct();

        await datasource.createTransaction(
          createSampleTransaction(id: 1),
        );

        await datasource.createTransaction(
          createSampleTransaction(id: 2),
        );

        final result = await datasource.getAllUserTransactions(userId);

        expect(result.data, isNotEmpty);
        expect(result.data?.length, 2);
      });

      test('returns an empty list for a user without transactions',
          () async {
        final result =
            await datasource.getAllUserTransactions('nonexistent_user');

        expect(result.data, isEmpty);
      });

      test('does not return another user transactions', () async {
        await createSampleProduct();

        await datasource.createTransaction(
          createSampleTransaction(),
        );

        final result =
            await datasource.getAllUserTransactions('different_user');

        expect(result.data, isEmpty);
      });

      test('retrieves transactions with ordered products', () async {
        await createSampleProduct();

        await datasource.createTransaction(
          createSampleTransaction(),
        );

        final result = await datasource.getAllUserTransactions(userId);

        expect(result.data?.first.orderedProducts, isNotEmpty);
        expect(result.data?.first.orderedProducts?.length, 1);
      });
    });

    group('deleteTransaction', () {
      test('deletes an existing transaction', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);

        final result =
            await datasource.deleteTransaction(transaction.id);

        expect(result.isSuccess, isTrue);

        final retrieved =
            await datasource.getTransaction(transaction.id);

        expect(retrieved.data, isNull);
      });

      test('restores stock when a transaction is deleted', () async {
        await createSampleProduct();

        final transaction = createSampleTransaction();

        await datasource.createTransaction(transaction);
        final result =
            await datasource.deleteTransaction(transaction.id);

        final product = await readProduct(1);

        expect(result.isSuccess, isTrue);
        expect(product['stock'], 50);
        expect(product['sold'], 10);
      });

      test('rejects deletion of a nonexistent transaction', () async {
        final result = await datasource.deleteTransaction(999);

        expect(result.isFailure, isTrue);
      });
    });
  });
}
