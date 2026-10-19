import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_media_service.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CatalogMediaService Unit & Integration Tests', () {
    late Directory tempDir;
    late Directory mediaDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogMediaService mediaService;
    late CatalogAndRecipeController catalogController;
    late OrderAndCheckoutController orderController;

    const managerStaff = Staff(
      id: 1,
      name: 'Manager Alice',
      departmentId: 3,
      pinHash: 'hash',
      role: StaffRole.supervisor,
      isActive: true,
      departmentName: 'Management',
    );

    const cashierStaff = Staff(
      id: 2,
      name: 'Cashier Bob',
      departmentId: 1,
      pinHash: 'hash',
      role: StaffRole.cashier,
      isActive: true,
      departmentName: 'Front Counter',
    );

    // Minimal valid 1x1 PNG
    final samplePngBytes = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    // Minimal valid JPEG
    final sampleJpgBytes = <int>[
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
      0x00, 0xBF, 0x00, 0xFF, 0xD9,
    ];

    // Minimal valid WebP
    final sampleWebpBytes = <int>[
      0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
      0x56, 0x50, 0x38, 0x4C, 0x0E, 0x00, 0x00, 0x00, 0x2F, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('catalog_media_test_');
      mediaDir = Directory('${tempDir.path}${Platform.pathSeparator}media');
      await mediaDir.create(recursive: true);
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_media.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      mediaService = CatalogMediaService(
        database: db,
        baseDirectoryPath: mediaDir.path,
      );
      catalogController = CatalogAndRecipeController(database: db);
      orderController = OrderAndCheckoutController(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rejects empty, corrupted or unsupported image bytes', () async {
      // Empty bytes
      expect(
        () async => mediaService.saveImage(
          staff: managerStaff,
          entityType: 'menu_item',
          entityId: 10,
          bytes: [],
          originalFileName: 'empty.jpg',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Unsupported plain text bytes
      final textBytes = 'Hello World this is not an image'.codeUnits;
      expect(
        () async => mediaService.saveImage(
          staff: managerStaff,
          entityType: 'menu_item',
          entityId: 10,
          bytes: textBytes,
          originalFileName: 'notes.txt',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects image exceeding size limit (5MB)', () async {
      final oversizedBytes = List<int>.filled(5 * 1024 * 1024 + 10, 0xFF);
      expect(
        () async => mediaService.saveImage(
          staff: managerStaff,
          entityType: 'menu_item',
          entityId: 10,
          bytes: oversizedBytes,
          originalFileName: 'huge.jpg',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('enforces role authorization: Cashier is rejected, Manager is permitted', () async {
      expect(
        () async => mediaService.saveImage(
          staff: cashierStaff,
          entityType: 'menu_item',
          entityId: 10,
          bytes: samplePngBytes,
          originalFileName: 'photo.png',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('safely persists uploaded image with relative DB path, checksum, and sets first image as primary', () async {
      final img = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'menu_item',
        entityId: 101,
        bytes: samplePngBytes,
        originalFileName: 'burger_front.png',
      );

      expect(img.id, greaterThan(0));
      expect(img.entityType, equals('menu_item'));
      expect(img.entityId, equals(101));
      expect(img.isPrimary, isTrue);
      expect(img.contentType, equals('image/png'));
      expect(img.byteCount, equals(samplePngBytes.length));
      expect(img.sha256Checksum, isNotEmpty);
      expect(img.relativeFilePath, startsWith('menu_items'));

      // Verify file exists on local filesystem at resolved path
      final resolvedFile = mediaService.resolveFile(img.relativeFilePath);
      expect(await resolvedFile.exists(), isTrue);
      expect(await resolvedFile.length(), equals(samplePngBytes.length));

      // Query primary image
      final primary = await mediaService.getPrimaryImage('menu_item', 101);
      expect(primary, isNotNull);
      expect(primary!.id, equals(img.id));
      expect(primary.isPrimary, isTrue);
    });

    test('supports multiple images per entity and switching primary thumbnail', () async {
      // First image (auto primary)
      final img1 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'deal',
        entityId: 5,
        bytes: sampleJpgBytes,
        originalFileName: 'deal_overview.jpg',
      );
      expect(img1.isPrimary, isTrue);

      // Second image (not primary by default)
      final img2 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'deal',
        entityId: 5,
        bytes: sampleWebpBytes,
        originalFileName: 'deal_close_up.webp',
      );
      expect(img2.isPrimary, isFalse);

      final images = await mediaService.getImagesForEntity('deal', 5);
      expect(images.length, equals(2));
      expect(images.first.id, equals(img1.id)); // Primary first

      // Switch primary to second image
      await mediaService.setPrimaryImage(img2.id, staff: managerStaff);

      final updatedImages = await mediaService.getImagesForEntity('deal', 5);
      expect(updatedImages.length, equals(2));
      final newPrimary = await mediaService.getPrimaryImage('deal', 5);
      expect(newPrimary?.id, equals(img2.id));
      expect(newPrimary?.isPrimary, isTrue);

      // Verify img1 is no longer primary
      final reloadedImg1 = updatedImages.firstWhere((i) => i.id == img1.id);
      expect(reloadedImg1.isPrimary, isFalse);
    });

    test('soft delete deactivates image and reassigns primary; permanent delete removes file', () async {
      final img1 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'menu_item',
        entityId: 200,
        bytes: samplePngBytes,
        originalFileName: 'dish_1.png',
      );
      final img2 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'menu_item',
        entityId: 200,
        bytes: sampleJpgBytes,
        originalFileName: 'dish_2.jpg',
      );

      // img1 is primary. Soft-delete img1
      await mediaService.deleteImage(img1.id, staff: managerStaff, permanent: false);

      final activeImages = await mediaService.getImagesForEntity('menu_item', 200, activeOnly: true);
      expect(activeImages.length, equals(1));
      expect(activeImages.first.id, equals(img2.id));

      // img2 should now be designated as primary
      final primaryAfterDelete = await mediaService.getPrimaryImage('menu_item', 200);
      expect(primaryAfterDelete?.id, equals(img2.id));
      expect(primaryAfterDelete?.isPrimary, isTrue);

      // Permanent delete on img2 removes file from disk
      final file2 = mediaService.resolveFile(img2.relativeFilePath);
      expect(await file2.exists(), isTrue);

      await mediaService.deleteImage(img2.id, staff: managerStaff, permanent: true);
      expect(await file2.exists(), isFalse);

      final remaining = await mediaService.getImagesForEntity('menu_item', 200, activeOnly: false);
      expect(remaining.any((i) => i.id == img2.id), isFalse);
    });

    test('menu items and deals with 0 images but valid recipes publish and sell normally', () async {
      // 1. Create raw ingredient and category
      final cat = await catalogController.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#FF5722',
      );
      final ing = await catalogController.createRawIngredient(
        name: 'Chicken Patty',
        storageUnit: StorageUnit.kg,
        currentStock: 100.0,
        costPerRecipeUnit: 400.0,
      );

      // 2. Create menu item draft (0 images attached)
      final item = await catalogController.createMenuItem(
        categoryId: cat.id,
        name: 'Crispy Burger',
        basePrice: 450.0,
      );

      // Attach valid BOM recipe
      await catalogController.setRecipeForMenuItem(
        menuItemId: item.id,
        items: [
          (rawIngredientId: ing.id, quantity: 0.15),
        ],
      );

      // Activate menu item with 0 images
      final activatedItem = await catalogController.updateMenuItem(item.copyWith(isActive: true));
      expect(activatedItem.isActive, isTrue);

      // Verify active menu item is listed for cashiers
      final cashierItems = await catalogController.getMenuItems(activeOnly: true);
      expect(cashierItems.any((i) => i.id == item.id), isTrue);

      // Verify media service returns null primary image without throwing
      final primaryImage = await mediaService.getPrimaryImage('menu_item', item.id);
      expect(primaryImage, isNull);

      // 3. Create deal with 0 images
      final deal = await orderController.createDeal(
        name: 'Duo Crispy Deal',
        basePrice: 800.0,
        items: [
          DealItemDraft(
            groupName: 'Burgers',
            defaultMenuItemId: item.id,
            options: [
              DealOptionDraft(menuItemId: item.id, upgradePrice: 0.0, isDefault: true),
            ],
          ),
        ],
      );
      expect(deal.isActive, isTrue);

      final primaryDealImage = await mediaService.getPrimaryImage('deal', deal.id);
      expect(primaryDealImage, isNull);

      // Verify deals list for cashiers includes the 0-image deal
      final activeDeals = await orderController.getDeals(activeOnly: true);
      expect(activeDeals.any((d) => d.id == deal.id), isTrue);
    });
  });
}
