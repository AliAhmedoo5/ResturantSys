import 'dart:typed_data';

/// A staged replacement or removal. Null means leave the saved photo unchanged.
class CatalogPhotoChange {
  CatalogPhotoChange.replace({required Uint8List bytes, required this.fileName})
      : bytes = Uint8List.fromList(bytes);

  const CatalogPhotoChange.remove() : bytes = null, fileName = null;

  final Uint8List? bytes;
  final String? fileName;
}
