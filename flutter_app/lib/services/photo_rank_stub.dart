import 'dart:typed_data';

Future<List<int>> rankCardImages(Uint8List bytes, List<String> urls) async =>
    List.generate(urls.length, (index) => index);
