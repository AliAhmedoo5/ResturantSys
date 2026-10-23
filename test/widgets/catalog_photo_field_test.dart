import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_media_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_photo_change.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/catalog/catalog_photo_field.dart';
import 'package:resturant_sys/widgets/catalog/dialogs/menu_item_form_dialog.dart';

// Native XFile derives its name from path, including for in-memory files.
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

void main() {
  setUpAll(() async {
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true' && await font.exists()) {
      final loader = FontLoader(WarmCounterTypography.fontFamily);
      loader.addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  testWidgets('browse stages one picture; cancel preserves it; remove stages removal', (tester) async {
    CatalogPhotoChange? change;
    bool busy = false;
    XFile? next = XFile.fromData(png, path: 'burger.png');
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: Center(child: SizedBox(width: 440, child: CatalogPhotoField(
        entityType: 'menu_item',
        pickFile: () async => next,
        onChanged: (value) => change = value,
        onBusyChanged: (value) => busy = value,
      )))),
    ));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('catalog_photo_browse')));
      for (var i = 0; busy && i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(busy, isFalse);
    expect(change?.bytes, png);
    expect(find.text('Change picture'), findsOneWidget);
    final previous = change;
    next = null;
    await tester.tap(find.byKey(const ValueKey('catalog_photo_browse')));
    await tester.pumpAndSettle();
    expect(change, same(previous));
    await tester.tap(find.byKey(const ValueKey('catalog_photo_remove')));
    await tester.pumpAndSettle();
    expect(change, isNotNull);
    expect(change!.bytes, isNull);
    expect(find.text('Add picture'), findsOneWidget);
  });

  testWidgets('drop rejects multiple, oversized and corrupt pictures without replacing selection', (tester) async {
    CatalogPhotoChange? change;
    bool busy = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 440,
      child: CatalogPhotoField(entityType: 'deal', onChanged: (value) => change = value,
        onBusyChanged: (value) => busy = value),
    ))));

    Future<void> drop(List<DropItem> files) async {
      await tester.runAsync(() async {
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(DropDoneDetails(
          files: files, localPosition: Offset.zero, globalPosition: Offset.zero,
        ));
        for (var i = 0; busy && i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(busy, isFalse);
    }

    await drop([DropItemFile.fromData(png, path: 'deal.png')]);
    expect(change?.bytes, png);
    final previous = change;
    await drop([DropItemFile.fromData(png, path: 'a.png'), DropItemFile.fromData(png, path: 'b.png')]);
    expect(find.text('Choose one picture at a time.'), findsOneWidget);
    expect(change, same(previous));
    await drop([DropItemFile.fromData(Uint8List(5 * 1024 * 1024 + 1), path: 'big.png')]);
    expect(find.text('Choose a non-empty picture up to 5 MB.'), findsOneWidget);
    expect(change, same(previous));
    await drop([DropItemFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'bad.png')]);
    expect(change, same(previous));
    // A valid PNG header alone still fails decoding.
    await drop([DropItemFile.fromData(Uint8List.sublistView(png, 0, 8), path: 'truncated.png')]);
    expect(change, same(previous));
    expect(find.textContaining('could not be read'), findsOneWidget);
    await drop([DropItemFile.fromData(png, path: 'photo.gif')]);
    expect(find.text('Choose a JPEG, PNG or WebP picture.'), findsOneWidget);
    expect(change, same(previous));
  });

  testWidgets('picture row stays compact at desktop size and supports keyboard selection', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var browseCount = 0;
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: RepaintBoundary(key: const ValueKey('photo_preview'), child: Scaffold(
        body: Center(child: SizedBox(width: 500, child: CatalogPhotoField(
          entityType: 'menu_item', onChanged: (_) {}, onBusyChanged: (_) {},
          pickFile: () async { browseCount++; return null; },
        ))),
      )),
    ));
    await tester.pumpAndSettle();
    final row = tester.getSize(find.byKey(const ValueKey('catalog_photo_drop_target')));
    expect(row.height, lessThanOrEqualTo(100));
    expect(row.width, 500);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(browseCount, 1);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('photo_preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/desktop-previews').create(recursive: true);
        await File('build/desktop-previews/catalog-picture.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('new Menu Item stages its picture until Save and fits 1366x768', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final posDb = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final directory = Directory.systemTemp.createTempSync('photo_form_test_');
    addTearDown(() async {
      await posDb.close();
      await directory.delete(recursive: true);
    });
    final db = await tester.runAsync(posDb.initialize);
    final service = CatalogMediaService(database: db!, baseDirectoryPath: directory.path);
    final catalog = CatalogAndRecipeController(database: db, mediaService: service);
    final category = (await tester.runAsync(() => catalog.createCategory(
      name: 'Burgers', displayOrder: 0, colorHex: '#FFC400',
    )))!;
    var saved = false;
    await tester.pumpWidget(RepaintBoundary(key: const ValueKey('form_preview'),
      child: MaterialApp(theme: WarmCounterTheme.darkTheme, home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          child: const Text('Open form'),
          onPressed: () => showDialog<void>(context: context, builder: (_) => MenuItemFormDialog(
            categories: [category], mediaService: service,
            onSave: ({required categoryId, required name, required basePrice, required taxRate,
              required isTaxInclusive, required isActive, required photoChange}) async {
              await catalog.createMenuItem(categoryId: categoryId, name: name, basePrice: basePrice,
                taxRate: taxRate, isTaxInclusive: isTaxInclusive, isActive: isActive, photoChange: photoChange);
              saved = true;
            },
          )),
        )),
      )),
    ));

    Future<void> openAndSelect() async {
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(DropDoneDetails(
          files: [DropItemFile.fromData(png, path: 'burger.png')],
          localPosition: Offset.zero, globalPosition: Offset.zero,
        ));
        for (var i = 0; i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('Change picture').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Change picture'), findsOneWidget);
    }

    await openAndSelect();
    expect(saved, isFalse);
    expect(await tester.runAsync(catalog.getMenuItems), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(catalog.getMenuItems), isEmpty);

    await openAndSelect();
    await tester.enterText(find.byKey(const ValueKey('menu_item_name_field')), 'Classic Burger');
    await tester.enterText(find.byKey(const ValueKey('menu_item_price_field')), '350');
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('save_menu_item_button'));
    expect(saveButton.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
      // Capture the overlay as well as the page behind the dialog.
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('form_preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/desktop-previews').create(recursive: true);
        await File('build/desktop-previews/menu-item-picture-form.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.runAsync(() async {
      await tester.tap(saveButton);
      for (var i = 0; !saved && i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    final items = (await tester.runAsync(catalog.getMenuItems))!;
    expect(items, hasLength(1));
    final images = await tester.runAsync(() => service.getImagesForEntity('menu_item', items.single.id));
    expect(images, hasLength(1));
  });
}
