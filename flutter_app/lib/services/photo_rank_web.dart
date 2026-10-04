import 'dart:js_interop';
import 'dart:typed_data';

@JS('pokeLensRankCardImages')
external JSPromise<JSArray<JSNumber>> _rankImages(
  JSUint8Array bytes,
  JSArray<JSString> urls,
);
Future<List<int>> rankCardImages(Uint8List bytes, List<String> urls) async {
  try {
    final result = await _rankImages(
      bytes.toJS,
      urls.map((url) => url.toJS).toList().toJS,
    ).toDart;
    return result.toDart.map((number) => number.toDartInt).toList();
  } catch (_) {
    return List.generate(urls.length, (index) => index);
  }
}
