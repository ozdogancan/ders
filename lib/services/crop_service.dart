import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../core/theme/koala_tokens.dart';
import '../views/crop_screen.dart';

/// Foto kırp + rotate servisi.
/// Web/Mobile fark etmeksizin **özel CropScreen**'i (tam ekran, snaphome
/// benzeri sade UI) açar — image_cropper'ın bottom toolbar'ı kullanıcı
/// tarafından istenmiyordu.
class CropService {
  CropService._();

  /// Kullanıcıya kırpma + rotate UI'ı gösterir. İptalde null döner.
  static Future<Uint8List?> cropAndRotate({
    required BuildContext context,
    required String sourcePath,
    required Uint8List sourceBytes,
  }) async {
    final result = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(imageBytes: sourceBytes),
      ),
    );
    return result;
  }

  /// Eski image_cropper akışı — şu an kullanılmıyor ama paket bağımlılığı
  /// kalsın diye tutuluyor; gerekirse advanced UI için tekrar açılabilir.
  // ignore: unused_element
  static Future<Uint8List?> _legacyImageCropper({
    required BuildContext context,
    required String sourcePath,
    required Uint8List sourceBytes,
  }) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Fotoğrafı Düzenle',
            toolbarColor: KoalaColors.bg,
            toolbarWidgetColor: KoalaColors.text,
            statusBarColor: KoalaColors.bg,
            backgroundColor: KoalaColors.bg,
            activeControlsWidgetColor: KoalaColors.accentDeep,
            cropFrameColor: KoalaColors.accentDeep,
            cropGridColor: Colors.white54,
            initAspectRatio: CropAspectRatioPreset.original,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Fotoğrafı Düzenle',
            doneButtonTitle: 'Devam et',
            cancelButtonTitle: 'İptal',
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.page,
            translations: const WebTranslations(
              title: '',
              rotateLeftTooltip: 'Sola döndür',
              rotateRightTooltip: 'Sağa döndür',
              cancelButton: 'İptal',
              cropButton: 'Devam et',
            ),
            themeData: const WebThemeData(
              rotateIconColor: KoalaColors.accentDeep,
            ),
          ),
        ],
      );
      if (cropped == null) return null;
      return await cropped.readAsBytes();
    } catch (e) {
      debugPrint('CropService error: $e — falling back to source bytes');
      return sourceBytes;
    }
  }
}
