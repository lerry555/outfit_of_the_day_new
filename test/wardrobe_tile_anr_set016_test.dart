import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';
import 'package:outfitofTheDay/utils/wardrobe_image_processing.dart';

void main() {
  test('wardrobe category preview only mounts the visible tile count', () {
    expect(kWardrobeCategoryPreviewTileCount, 3);
    expect(kWardrobeTileImageCacheWidth, 384);
    expect(kWardrobeDetailImageCacheWidth, 1080);
  });

  test('V2 uiProjection category is used when canonical type is absent', () {
    final key = ClothingKnowledgeBase.wardrobeDisplayCategoryKey({
      'name': 'Biela klasická košeľa',
      'uiProjection': {
        'mainCategory': 'oblecenie',
        'category': 'kosele',
      },
    });
    expect(key, 'kosele');
  });

  testWidgets('wardrobe tile images decode at the bounded cache width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 120,
          child: wardrobeItemImage(
            data: const {'imageUrl': 'https://example.test/shirt.png'},
            imageUrl: 'https://example.test/shirt.png',
            showSpinner: false,
            cacheWidth: kWardrobeTileImageCacheWidth,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final resized = image.image as ResizeImage;
    expect(resized.width, kWardrobeTileImageCacheWidth);
  });

  test('wardrobe glass chrome must not use BackdropFilter', () {
    final src = File('lib/screens/wardrobe_screen.dart').readAsStringSync();
    expect(src.contains('BackdropFilter'), isFalse);
    expect(src.contains('ImageFilter.blur'), isFalse);
  });

  test('home edit overlay and quick-orb must not use BackdropFilter', () {
    expect(
      File('lib/screens/home_screen.dart').readAsStringSync().contains(
        'BackdropFilter(',
      ),
      isFalse,
    );
    expect(
      File(
        'lib/widgets/home/home_quick_action_orb.dart',
      ).readAsStringSync().contains('BackdropFilter('),
      isFalse,
    );
  });
}
