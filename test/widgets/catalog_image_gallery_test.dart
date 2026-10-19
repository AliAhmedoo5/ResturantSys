import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_media_service.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/catalog/dialogs/catalog_photo_gallery_dialog.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CatalogPhotoGalleryDialog & Supervisor Workspace Widget Tests', () {
    late Directory tempDir;
    late Directory mediaDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogMediaService mediaService;
    late CatalogAndRecipeController catalogController;

    const managerStaff = Staff(
      id: 1,
      name: 'Manager Alice',
      departmentId: 3,
      pinHash: 'hash',
      role: StaffRole.supervisor,
      isActive: true,
      departmentName: 'Management',
    );

    // 1x1 Transparent PNG
    final samplePng = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gallery_widget_test_');
      mediaDir = Directory('${tempDir.path}${Platform.pathSeparator}media');
      await mediaDir.create(recursive: true);
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_gallery.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      mediaService = CatalogMediaService(
        database: db,
        baseDirectoryPath: mediaDir.path,
      );
      catalogController = CatalogAndRecipeController(
        database: db,
        mediaService: mediaService,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('renders empty gallery and uploads sample photo', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: CatalogPhotoGalleryDialog(
              mediaService: mediaService,
              entityType: 'menu_item',
              entityId: 42,
              entityName: 'Smash Double Burger',
              currentStaff: managerStaff,
              initialImages: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty state visible
      expect(find.text('No photos attached yet.'), findsOneWidget);
      expect(find.textContaining('Items and deals with valid recipes sell normally with 0 photos.'), findsOneWidget);

      // Open Add Photo section
      final addPhotoButton = find.byKey(const ValueKey('open_add_photo_button'));
      expect(addPhotoButton, findsOneWidget);
      await tester.tap(addPhotoButton);
      await tester.pumpAndSettle();

      // Sample upload button
      final sampleUploadButton = find.byKey(const ValueKey('add_sample_photo_button'));
      expect(sampleUploadButton, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(sampleUploadButton);
        await Future.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });
      await tester.pump();

      // After upload, empty state disappears and primary badge is shown
      expect(find.text('No photos attached yet.'), findsNothing);
      expect(find.text('PRIMARY'), findsOneWidget);
    });

    testWidgets('manages multiple photos: primary designation and deletion', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Seed two images in service
      final img1 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'deal',
        entityId: 7,
        bytes: samplePng,
        originalFileName: 'deal_primary.png',
      );
      final img2 = await mediaService.saveImage(
        staff: managerStaff,
        entityType: 'deal',
        entityId: 7,
        bytes: samplePng,
        originalFileName: 'deal_secondary.png',
        isPrimary: false,
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: WarmCounterTheme.lightTheme,
            home: Scaffold(
              body: CatalogPhotoGalleryDialog(
                mediaService: mediaService,
                entityType: 'deal',
                entityId: 7,
                entityName: 'Super Saver Meal',
                currentStaff: managerStaff,
                initialImages: [img1, img2],
              ),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      // Both images listed
      expect(find.byKey(ValueKey('gallery_image_tile_${img1.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('gallery_image_tile_${img2.id}')), findsOneWidget);

      // img1 has PRIMARY badge, img2 has "Make Primary" button
      expect(find.byKey(ValueKey('primary_badge_${img1.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('set_primary_image_${img2.id}')), findsOneWidget);

      // Tap "Make Primary" on img2
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('set_primary_image_${img2.id}')));
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      await tester.pump();

      // img2 is now primary
      expect(find.byKey(ValueKey('primary_badge_${img2.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('set_primary_image_${img1.id}')), findsOneWidget);

      // Delete img1
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('delete_image_${img1.id}')));
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      await tester.pump();

      // Only img2 remains
      expect(find.byKey(ValueKey('gallery_image_tile_${img1.id}')), findsNothing);
      expect(find.byKey(ValueKey('gallery_image_tile_${img2.id}')), findsOneWidget);
    });

    testWidgets('supervisor workspace has photo button that launches photo gallery dialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const cat = MenuCategory(id: 1, name: 'Burgers', displayOrder: 1, colorHex: '#E53935');
      const item = MenuItem(
        id: 10,
        categoryId: 1,
        categoryName: 'Burgers',
        name: 'Gourmet Beef Burger',
        basePrice: 750.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(
              controller: catalogController,
              initialCategories: [cat],
              initialMenuItems: [item],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Menu Items tab
      await tester.tap(find.byKey(const ValueKey('tab_menu_items')));
      await tester.pumpAndSettle();

      // Manage photos button is present
      final managePhotosButton = find.byKey(const ValueKey('manage_photos_button_10'));
      expect(managePhotosButton, findsOneWidget);

      // Tap button to open gallery dialog
      await tester.tap(managePhotosButton);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Photos: Gourmet Beef Burger'), findsOneWidget);
      expect(find.byKey(const ValueKey('close_photo_gallery_button')), findsOneWidget);

      // Close dialog
      await tester.tap(find.byKey(const ValueKey('close_photo_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.text('Photos: Gourmet Beef Burger'), findsNothing);
    });
  });
}
