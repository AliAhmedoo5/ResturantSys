import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_media_service.dart';
import 'package:resturant_sys/core/catalog/catalog_photo_change.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  late PosDatabase posDb;
  late Database db;
  late Directory directory;
  late CatalogMediaService media;
  late CatalogAndRecipeController catalog;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('single_photo_test_');
    posDb = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    db = await posDb.initialize();
    media = CatalogMediaService(database: db, baseDirectoryPath: directory.path);
    catalog = CatalogAndRecipeController(database: db, mediaService: media);
  });
  tearDown(() async {
    await posDb.close();
    await directory.delete(recursive: true);
  });
  CatalogPhotoChange replacement() => CatalogPhotoChange.replace(bytes: png, fileName: 'burger.png');

  test('create, replace, unchanged save and remove keep one active photo', () async {
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#FFC400');
    final item = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 350,
      photoChange: replacement());
    final first = (await media.getImagesForEntity('menu_item', item.id)).single;
    await catalog.updateMenuItem(item.copyWith(name: 'Classic Burger'));
    expect((await media.getImagesForEntity('menu_item', item.id)).single.id, first.id);
    await catalog.updateMenuItem(item, photoChange: replacement());
    final second = (await media.getImagesForEntity('menu_item', item.id)).single;
    expect(second.id, isNot(first.id));
    expect(second.isPrimary, isTrue);
    expect(await media.resolveFile(first.relativeFilePath).exists(), isTrue);
    expect(await media.resolveFile(second.relativeFilePath).readAsBytes(), png);
    await catalog.updateMenuItem(item, photoChange: const CatalogPhotoChange.remove());
    expect(await media.getImagesForEntity('menu_item', item.id), isEmpty);
  });

  test('failed photo insert rolls back item creation and cleans new files; retry creates once', () async {
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#FFC400');
    await db.execute("CREATE TRIGGER reject_photo BEFORE INSERT ON catalog_images BEGIN SELECT RAISE(ABORT, 'simulated failure'); END");
    await expectLater(catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 350,
      photoChange: replacement()), throwsA(isA<DatabaseException>()));
    expect(await catalog.getMenuItems(), isEmpty);
    expect(await directory.list(recursive: true).where((entry) => entry is File).toList(), isEmpty);
    await db.execute('DROP TRIGGER reject_photo');
    await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 350,
      photoChange: replacement());
    expect(await catalog.getMenuItems(), hasLength(1));
  });

  test('failed replacement preserves old picture and item fields', () async {
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#FFC400');
    final item = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 350,
      photoChange: replacement());
    final first = (await media.getImagesForEntity('menu_item', item.id)).single;
    await db.execute("CREATE TRIGGER reject_photo BEFORE INSERT ON catalog_images BEGIN SELECT RAISE(ABORT, 'simulated failure'); END");
    await expectLater(catalog.updateMenuItem(item.copyWith(name: 'Changed'), photoChange: replacement()),
      throwsA(isA<DatabaseException>()));
    expect((await catalog.getMenuItem(item.id)).name, 'Burger');
    expect((await media.getImagesForEntity('menu_item', item.id)).single.id, first.id);
  });

  test('Deal replacement retires all legacy gallery entries; removal leaves no primary', () async {
    for (var i = 0; i < 2; i++) {
      await media.saveImage(entityType: 'deal', entityId: 7, bytes: png, originalFileName: 'legacy.png');
    }
    await media.saveEntityWithPhoto(entityType: 'deal', saveEntity: (_) async => 7, photoChange: replacement());
    expect(await media.getImagesForEntity('deal', 7), hasLength(1));
    await media.saveEntityWithPhoto(entityType: 'deal', saveEntity: (_) async => 7,
      photoChange: const CatalogPhotoChange.remove());
    expect(await media.getPrimaryImage('deal', 7), isNull);
    expect(await media.getPrimaryImagesForEntities('deal'), isEmpty);
  });
}
