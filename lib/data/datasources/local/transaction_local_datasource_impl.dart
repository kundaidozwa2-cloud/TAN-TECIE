import 'package:sqflite/sqflite.dart';

import '../../../core/common/result.dart';
import '../../../core/services/database/database_config.dart';
import '../../../core/services/database/database_service.dart';
import '../../models/ordered_product_model.dart';
import '../../models/product_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../interfaces/transaction_datasource.dart';

class TransactionLocalDatasourceImpl extends TransactionDatasource {
  final DatabaseService _databaseService;

  TransactionLocalDatasourceImpl(this._databaseService);

  @override
  Future<Result<int>> createTransaction(TransactionModel transaction) async {
    try {
      await _databaseService.database.transaction((trx) async {
        final existing = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
        if (existing.isNotEmpty) {
          throw StateError('This transaction ID already exists.');
        }

        final items = transaction.orderedProducts ?? [];
        final quantities = <int, int>{};

        for (final item in items) {
          if (item.quantity <= 0) {
            throw StateError('Product quantity must be greater than zero.');
          }
          quantities[item.productId] =
              (quantities[item.productId] ?? 0) + item.quantity;
        }

        for (final entry in quantities.entries) {
          final rows = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );
          if (rows.isEmpty) {
            throw StateError('A product in this sale no longer exists.');
          }

          final product = ProductModel.fromJson(rows.first);
          if (product.stock < entry.value) {
            throw StateError(
              'Insufficient stock for ${product.name}. Available: ${product.stock}, requested: ${entry.value}.',
            );
          }
        }

        await trx.insert(
          DatabaseConfig.transactionTableName,
          transaction.toJson()
            ..remove('orderedProducts')
            ..remove('createdBy'),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        for (final entry in quantities.entries) {
          final rows = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );
          final product = ProductModel.fromJson(rows.first);

          await trx.update(
            DatabaseConfig.productTableName,
            {
              'stock': product.stock - entry.value,
              'sold': product.sold + entry.value,
            },
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }

        for (final item in items) {
          item.transactionId = transaction.id;
          await trx.insert(
            DatabaseConfig.orderedProductTableName,
            item.toJson(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      });

      return Result.success(data: transaction.id);
    } catch (e) {
      return Result.failure(error: e);
    }
  }

  @override
  Future<Result<void>> updateTransaction(TransactionModel transaction) async {
    try {
      await _databaseService.database.transaction((trx) async {
        final existing = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
        if (existing.isEmpty) {
          throw StateError('Cannot edit a sale that does not exist.');
        }

        final oldItems = await trx.query(
          DatabaseConfig.orderedProductTableName,
          where: 'transactionId = ?',
          whereArgs: [transaction.id],
        );

        // Restore the original sale quantities before applying the revision.
        final oldQuantities = <int, int>{};
        for (final row in oldItems) {
          final item = OrderedProductModel.fromJson(row);
          oldQuantities[item.productId] =
              (oldQuantities[item.productId] ?? 0) + item.quantity;
        }

        for (final entry in oldQuantities.entries) {
          final rows = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );
          if (rows.isNotEmpty) {
            final product = ProductModel.fromJson(rows.first);
            await trx.update(
              DatabaseConfig.productTableName,
              {
                'stock': product.stock + entry.value,
                'sold': (product.sold - entry.value).clamp(0, 2147483647),
              },
              where: 'id = ?',
              whereArgs: [entry.key],
            );
          }
        }

        final newItems = transaction.orderedProducts ?? [];
        final newQuantities = <int, int>{};

        for (final item in newItems) {
          if (item.quantity <= 0) {
            throw StateError('Product quantity must be greater than zero.');
          }
          newQuantities[item.productId] =
              (newQuantities[item.productId] ?? 0) + item.quantity;
        }

        // Check all revised quantities before deducting any stock.
        for (final entry in newQuantities.entries) {
          final rows = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );
          if (rows.isEmpty) {
            throw StateError('A product in this revised sale does not exist.');
          }

          final product = ProductModel.fromJson(rows.first);
          if (product.stock < entry.value) {
            throw StateError(
              'Insufficient stock for ${product.name}. Available: ${product.stock}, requested: ${entry.value}.',
            );
          }
        }

        await trx.update(
          DatabaseConfig.transactionTableName,
          transaction.toJson()
            ..remove('orderedProducts')
            ..remove('createdBy'),
          where: 'id = ?',
          whereArgs: [transaction.id],
        );

        await trx.delete(
          DatabaseConfig.orderedProductTableName,
          where: 'transactionId = ?',
          whereArgs: [transaction.id],
        );

        for (final entry in newQuantities.entries) {
          final rows = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );
          final product = ProductModel.fromJson(rows.first);

          await trx.update(
            DatabaseConfig.productTableName,
            {
              'stock': product.stock - entry.value,
              'sold': product.sold + entry.value,
            },
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }

        for (final item in newItems) {
          item.transactionId = transaction.id;
          await trx.insert(
            DatabaseConfig.orderedProductTableName,
            item.toJson(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      });

      return Result.success(data: null);
    } catch (e) {
      return Result.failure(error: e);
    }
  }

  @override
  Future<Result<void>> deleteTransaction(int id) async {
    try {
      await _databaseService.database.transaction((trx) async {
        final existing = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (existing.isEmpty) {
          throw StateError('This transaction does not exist.');
        }

        final rows = await trx.query(
          DatabaseConfig.orderedProductTableName,
          where: 'transactionId = ?',
          whereArgs: [id],
        );

        final quantities = <int, int>{};
        for (final row in rows) {
          final item = OrderedProductModel.fromJson(row);
          quantities[item.productId] =
              (quantities[item.productId] ?? 0) + item.quantity;
        }

        for (final entry in quantities.entries) {
          final products = await trx.query(
            DatabaseConfig.productTableName,
            where: 'id = ?',
            whereArgs: [entry.key],
          );

          if (products.isNotEmpty) {
            final product = ProductModel.fromJson(products.first);
            await trx.update(
              DatabaseConfig.productTableName,
              {
                'stock': product.stock + entry.value,
                'sold': (product.sold - entry.value).clamp(0, 2147483647),
              },
              where: 'id = ?',
              whereArgs: [entry.key],
            );
          }
        }

        await trx.delete(
          DatabaseConfig.orderedProductTableName,
          where: 'transactionId = ?',
          whereArgs: [id],
        );

        await trx.delete(
          DatabaseConfig.transactionTableName,
          where: 'id = ?',
          whereArgs: [id],
        );
      });

      return Result.success(data: null);
    } catch (e) {
      return Result.failure(error: e);
    }
  }

  @override
  Future<Result<TransactionModel?>> getTransaction(int id) async {
    try {
      final transaction = await _databaseService.database.transaction((trx) async {
        // Get transaction
        var rawTransactions = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'id = ?',
          whereArgs: [id],
        );

        if (rawTransactions.isEmpty) {
          return null;
        }

        var transaction = TransactionModel.fromJson(rawTransactions.first);

        // Get transaction ordered products
        var rawOrderedProducts = await trx.query(
          DatabaseConfig.orderedProductTableName,
          where: 'transactionId = ?',
          whereArgs: [id],
        );

        var orderedProducts = rawOrderedProducts.map((e) => OrderedProductModel.fromJson(e)).toList();

        // Set ordered products to transaction
        transaction.orderedProducts = orderedProducts;

        // Get created by
        var rawCreatedBy = await trx.query(
          DatabaseConfig.userTableName,
          where: 'id = ?',
          whereArgs: [transaction.createdById],
        );

        // Set created by to transaction
        if (rawCreatedBy.isNotEmpty) {
          transaction.createdBy = UserModel.fromJson(rawCreatedBy.first);
        }

        return transaction;
      });

      return Result.success(data: transaction);
    } catch (e) {
      return Result.failure(error: e);
    }
  }

  @override
  Future<Result<List<TransactionModel>>> getAllUserTransactions(String userId) async {
    try {
      final transactions = await _databaseService.database.transaction((trx) async {
        var rawTransactions = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'createdById = ?',
          whereArgs: [userId],
          orderBy: 'createdAt DESC',
        );

        var transactions = rawTransactions.map((e) => TransactionModel.fromJson(e)).toList();

        // Use batch processing for better performance
        for (var transaction in transactions) {
          // Get transaction ordered products
          var rawOrderedProducts = await trx.query(
            DatabaseConfig.orderedProductTableName,
            where: 'transactionId = ?',
            whereArgs: [transaction.id],
          );

          var orderedProducts = rawOrderedProducts.map((e) => OrderedProductModel.fromJson(e)).toList();

          // Set ordered products to transaction
          transaction.orderedProducts = orderedProducts;

          // Get created by
          var rawCreatedBy = await trx.query(
            DatabaseConfig.userTableName,
            where: 'id = ?',
            whereArgs: [transaction.createdById],
          );

          // Set created by to transaction
          if (rawCreatedBy.isNotEmpty) {
            transaction.createdBy = UserModel.fromJson(rawCreatedBy.first);
          }
        }

        return transactions;
      });

      return Result.success(data: transactions);
    } catch (e) {
      return Result.failure(error: e);
    }
  }

  @override
  Future<Result<List<TransactionModel>>> getUserTransactions(
    String userId, {
    String orderBy = 'createdAt',
    String sortBy = 'DESC',
    int limit = 10,
    int? offset,
    String? contains,
  }) async {
    try {
      final transactions = await _databaseService.database.transaction((trx) async {
        var rawTransactions = await trx.query(
          DatabaseConfig.transactionTableName,
          where: 'createdById = ? AND id LIKE ?',
          whereArgs: [userId, "%${contains ?? ''}%"],
          orderBy: '$orderBy $sortBy',
          limit: limit,
          offset: offset,
        );

        var transactions = rawTransactions.map((e) => TransactionModel.fromJson(e)).toList();

        for (var transaction in transactions) {
          // Get transaction ordered products
          var rawOrderedProducts = await trx.query(
            DatabaseConfig.orderedProductTableName,
            where: 'transactionId = ?',
            whereArgs: [transaction.id],
          );

          var orderedProducts = rawOrderedProducts.map((e) => OrderedProductModel.fromJson(e)).toList();

          // Set ordered products to transaction
          transaction.orderedProducts = orderedProducts;

          // Get created by
          var rawCreatedBy = await trx.query(
            DatabaseConfig.userTableName,
            where: 'id = ?',
            whereArgs: [transaction.createdById],
          );

          // Set created by to transaction
          if (rawCreatedBy.isNotEmpty) {
            transaction.createdBy = UserModel.fromJson(rawCreatedBy.first);
          }
        }

        return transactions;
      });

      return Result.success(data: transactions);
    } catch (e) {
      return Result.failure(error: e);
    }
  }
}
