import 'dart:convert';
import 'dart:typed_data';

import 'context.dart';

/// Represents an uploaded file parsed from a multipart/form-data request.
class UploadedFile {
  /// The form field name (e.g. `avatar`, `document`).
  final String name;

  /// The original filename sent by the client (e.g. `report.pdf`).
  final String? filename;

  /// The MIME content-type of the file (e.g. `image/png`, `application/pdf`).
  final String? contentType;

  /// The raw file bytes.
  final Uint8List bytes;

  const UploadedFile({
    required this.name,
    this.filename,
    this.contentType,
    required this.bytes,
  });

  /// File size in bytes.
  int get size => bytes.length;

  /// Read file content as UTF-8 string.
  String readAsString() => utf8.decode(bytes);
}

/// Parsed form data containing text fields and uploaded files.
class FormData {
  final Map<String, String> fields;
  final List<UploadedFile> files;

  const FormData({
    this.fields = const {},
    this.files = const [],
  });

  /// Get form field value by name.
  String? field(String name) => fields[name];

  /// Get first uploaded file by field name.
  UploadedFile? file(String name) {
    for (final f in files) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Get all uploaded files matching a field name.
  List<UploadedFile> allFiles(String name) {
    return files.where((f) => f.name == name).toList();
  }
}

/// Zero-dependency parser for `multipart/form-data` HTTP requests.
class MultipartParser {
  static FormData? parse(EndveinContext ctx) {
    final contentType = ctx.getHeader('content-type');
    if (contentType == null || !contentType.toLowerCase().contains('multipart/form-data')) {
      return null;
    }

    final rawBytes = ctx.rawBody;
    if (rawBytes == null || rawBytes.isEmpty) {
      return const FormData();
    }

    // 1. Extract boundary delimiter from Content-Type
    final boundaryMatch = RegExp(r'boundary=([^;]+)', caseSensitive: false).firstMatch(contentType);
    if (boundaryMatch == null) return null;

    var boundaryStr = boundaryMatch.group(1)!.trim();
    if (boundaryStr.startsWith('"') && boundaryStr.endsWith('"')) {
      boundaryStr = boundaryStr.substring(1, boundaryStr.length - 1);
    }

    final delimiter = ascii.encode('--$boundaryStr');

    final fields = <String, String>{};
    final files = <UploadedFile>[];

    // 2. Find all occurrences of boundary delimiter
    final indices = <int>[];
    for (var i = 0; i <= rawBytes.length - delimiter.length; i++) {
      var match = true;
      for (var j = 0; j < delimiter.length; j++) {
        if (rawBytes[i + j] != delimiter[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        indices.add(i);
        i += delimiter.length - 1;
      }
    }

    if (indices.length < 2) return const FormData();

    // 3. Parse each part between boundaries
    for (var k = 0; k < indices.length - 1; k++) {
      var start = indices[k] + delimiter.length;
      // Skip trailing \r\n after boundary
      if (start + 2 <= rawBytes.length && rawBytes[start] == 13 && rawBytes[start + 1] == 10) {
        start += 2;
      }

      var end = indices[k + 1];
      // Trim preceding \r\n before next boundary
      if (end >= 2 && rawBytes[end - 2] == 13 && rawBytes[end - 1] == 10) {
        end -= 2;
      }

      if (start >= end) continue;

      // Find header boundary \r\n\r\n (13, 10, 13, 10)
      var headerEnd = -1;
      for (var i = start; i <= end - 4; i++) {
        if (rawBytes[i] == 13 &&
            rawBytes[i + 1] == 10 &&
            rawBytes[i + 2] == 13 &&
            rawBytes[i + 3] == 10) {
          headerEnd = i;
          break;
        }
      }

      if (headerEnd == -1) continue;

      final headerBytes = Uint8List.sublistView(rawBytes, start, headerEnd);
      final headerStr = utf8.decode(headerBytes);
      final bodyBytes = Uint8List.sublistView(rawBytes, headerEnd + 4, end);

      // Parse Part Headers
      String? name;
      String? filename;
      String? partContentType;

      for (final line in headerStr.split('\r\n')) {
        final colonIdx = line.indexOf(':');
        if (colonIdx == -1) continue;

        final hName = line.substring(0, colonIdx).trim().toLowerCase();
        final hVal = line.substring(colonIdx + 1).trim();

        if (hName == 'content-disposition') {
          final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(hVal);
          if (nameMatch != null) name = nameMatch.group(1);

          final fileMatch = RegExp(r'filename="([^"]+)"').firstMatch(hVal);
          if (fileMatch != null) filename = fileMatch.group(1);
        } else if (hName == 'content-type') {
          partContentType = hVal;
        }
      }

      if (name == null) continue;

      if (filename != null) {
        files.add(UploadedFile(
          name: name,
          filename: filename,
          contentType: partContentType ?? 'application/octet-stream',
          bytes: Uint8List.fromList(bodyBytes),
        ));
      } else {
        fields[name] = utf8.decode(bodyBytes);
      }
    }

    return FormData(fields: fields, files: files);
  }
}

/// Extension on [EndveinContext] to effortlessly parse multipart/form-data.
extension ContextMultipartX on EndveinContext {
  /// Parse incoming request body as [FormData] containing fields and files.
  FormData? multipart() => MultipartParser.parse(this);
}
