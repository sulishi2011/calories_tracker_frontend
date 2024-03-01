@JS()
// Specify the library name using the library directive at the top
library js_interop;

// Now, import the js package
import 'package:js/js.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:js/js_util.dart' as js_util;

// Declare external functions corresponding to your JavaScript functions
@JS('startRecording')
external void startRecording();

@JS('stopRecording')
external Future<String> stopRecording();

@JS('blobUrlToArrayBuffer')
external void _blobUrlToArrayBuffer(String blobUrl, void Function(BlobConversionResult result) callback);

Future<Uint8List?> blobUrlToUint8List(String blobUrl) async {
  Completer<Uint8List?> completer = Completer();

  _blobUrlToArrayBuffer(blobUrl, allowInterop((BlobConversionResult result) {
    print("Dart callback invoked.");
    if (result.error == null) {
      print("Received data size: ${result.data?.length} bytes");
      completer.complete(result.data);
    } else {
      print("Error converting blob URL to Uint8List: ${result.error}");
      completer.completeError("Error converting blob URL to Uint8List: ${result.error}");
    }
  }));

  return completer.future;
}
List<int> jsArrayToList(dynamic jsArray) {
  // Assuming you have a way to convert JS Array to Dart List<int>
  // This might require your own implementation based on how you're getting the data
  // For simplicity, this is a placeholder function
  return List<int>.from(jsArray);
}

@JS()
@anonymous
class BlobConversionResult {
  external factory BlobConversionResult({Uint8List? data, String? error});
  external Uint8List get data;
  external String get error;
}

@JS('releaseBlobUrl')
external void releaseBlobUrl(String blobUrl);