import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:http_cache_stream/src/models/http_range/http_range_response.dart';

import '../../etc/mime_types.dart';
import '../exceptions/http_exceptions.dart';
import '../files/cache_files.dart';

@immutable
class CachedResponseHeaders {
  final Map<String, String> _headers;
  CachedResponseHeaders._(this._headers);

  ///Compares this [CachedResponseHeaders] to the given [next] [CachedResponseHeaders] to determine if the cache is outdated.
  ///CachedResponseHeaders.fromFile() supports validating against a HEAD request by comparing sourceLength and lastModified.
  static bool validateCacheResponse(final CachedResponseHeaders previous, final CachedResponseHeaders next) {
    if (previous.eTag != null && next.eTag != null) {
      return previous.eTag == next.eTag;
    }

    final previousLastModified = previous.lastModified;
    if (previousLastModified != null) {
      final nextLastModified = next.lastModified;
      if (nextLastModified != null && nextLastModified.isAfter(previousLastModified)) {
        return false;
      }
    }

    if (previous.sourceLength != null && next.sourceLength != null) {
      return previous.sourceLength == next.sourceLength;
    }
    return previous.contentLength == next.contentLength;
  }

  String? get(String key) => _headers[key];

  ///If the host supports range requests.
  late final bool acceptsRangeRequests = equals(
    HttpHeaders.acceptRangesHeader,
    'bytes',
  );

  bool canResumeDownload() => acceptsRangeRequests && !isCompressedOrChunked;

  bool shouldRevalidate() {
    final expirationDateTime = cacheExpirationDateTime;
    return expirationDateTime == null || DateTime.now().isAfter(expirationDateTime);
  }

  DateTime? get cacheExpirationDateTime {
    final expiresHeaderDateTime = parseHeaderDateTime(
      HttpHeaders.expiresHeader,
    );
    if (expiresHeaderDateTime != null) {
      return expiresHeaderDateTime;
    }
    final cacheControl = get(HttpHeaders.cacheControlHeader);
    if (cacheControl == null) return null;
    final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    if (maxAgeMatch == null) return null;
    final maxAgeSeconds = int.tryParse(maxAgeMatch.group(1)!);
    if (maxAgeSeconds == null || maxAgeSeconds <= 0) return null;
    final responseDate = parseHeaderDateTime(HttpHeaders.dateHeader);
    if (responseDate == null) return null;
    return responseDate.add(Duration(seconds: maxAgeSeconds));
  }

  ContentType? get contentType {
    final contentTypeHeader = get(HttpHeaders.contentTypeHeader);
    return contentTypeHeader == null ? null : ContentType.parse(contentTypeHeader);
  }

  String? get eTag => get(HttpHeaders.etagHeader);

  ///Gets the source length of the response. This is used to determine the total length of the response data.
  ///Returns null if the source length is unknown (e.g. for compressed or chunked responses). Otherwise, returns a positive integer.
  late final int? sourceLength = isCompressedOrChunked ? null : contentLength;

  int? get contentLength {
    final contentLengthValue = get(HttpHeaders.contentLengthHeader);
    if (contentLengthValue == null) return null;
    final length = int.tryParse(contentLengthValue) ?? -1;
    return length > 0 ? length : null;
  }

  /// Returns true if the response is compressed or chunked. This means that the content length != source length, and the source length cannot be determined until the download is complete.
  bool get isCompressedOrChunked {
    return equals(HttpHeaders.contentEncodingHeader, 'gzip') || equals(HttpHeaders.transferEncodingHeader, 'chunked');
  }

  DateTime? get lastModified => parseHeaderDateTime(HttpHeaders.lastModifiedHeader);
  DateTime? get responseDate => parseHeaderDateTime(HttpHeaders.dateHeader);

  ///Attempts to parse [DateTime] from the given [httpHeader].
  DateTime? parseHeaderDateTime(String httpHeader) {
    final value = get(httpHeader);
    if (value == null || value.isEmpty) return null;
    try {
      return HttpDate.parse(value); // Try to parse the date (not all servers return a valid date)
    } catch (e) {
      return null;
    }
  }

  bool equals(String httpHeader, String? value) => get(httpHeader) == value;

  ///Sets the source length of the response. This is used once all data from a compressed or chunked response has been received.
  CachedResponseHeaders setSourceLength(final int sourceLength) {
    final Map<String, String> headers = {..._headers};
    headers[HttpHeaders.acceptRangesHeader] = 'bytes';
    headers[HttpHeaders.contentLengthHeader] = sourceLength.toString();
    headers.remove(HttpHeaders.contentRangeHeader);
    headers.remove(HttpHeaders.contentEncodingHeader);
    headers.remove(HttpHeaders.transferEncodingHeader);
    return CachedResponseHeaders._(headers);
  }

  /// Filters the headers to only include essential headers for caching.
  CachedResponseHeaders essentialHeaders() {
    final Map<String, String> retainedHeaders = {};

    const List<String> essentialHeaders = [
      HttpHeaders.contentLengthHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.contentTypeHeader,
      HttpHeaders.lastModifiedHeader,
      HttpHeaders.dateHeader,
      HttpHeaders.expiresHeader,
      HttpHeaders.cacheControlHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.contentEncodingHeader,
      HttpHeaders.transferEncodingHeader,
    ];

    for (final header in essentialHeaders) {
      final value = _headers[header];
      if (value != null) {
        retainedHeaders[header] = value;
      }
    }

    return CachedResponseHeaders._(retainedHeaders);
  }

  ///Extracts [CachedResponseHeaders] from a [BaseResponse].
  ///If the response is a range response, the content range header is removed, and the source length is set to the range source length.
  factory CachedResponseHeaders.fromBaseResponse(BaseResponse response) {
    final Map<String, String> headers = {...response.headers};

    if (headers.remove(HttpHeaders.contentRangeHeader) != null) {
      headers[HttpHeaders.acceptRangesHeader] = 'bytes'; // Ensure accept-ranges is set to bytes for range responses. Not all servers do this.

      final HttpRangeResponse? rangeResponse = HttpRangeResponse.parse(response);
      if (rangeResponse != null) {
        final int? rangeSourceLength = rangeResponse.sourceLength;
        if (rangeSourceLength != null) {
          headers[HttpHeaders.contentLengthHeader] = rangeSourceLength.toString();
        } else if (!rangeResponse.isFull) {
          headers.remove(HttpHeaders.contentLengthHeader);
        }
      }
    }

    return CachedResponseHeaders._(headers);
  }

  ///Constructs a [CachedResponseHeaders] object from the given [url] by sending a HEAD request.
  static Future<CachedResponseHeaders> fromUrl(
    final Uri url, {
    final http.Client? httpClient,
    Map<String, String> requestHeaders = const {},
  }) async {
    if (!requestHeaders.containsKey(HttpHeaders.acceptEncodingHeader)) {
      requestHeaders = {...requestHeaders, HttpHeaders.acceptEncodingHeader: 'identity'};
    }
    final response = await (httpClient?.head(url, headers: requestHeaders) ?? http.head(url, headers: requestHeaders)).timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      throw HttpStatusCodeException(url, HttpStatus.ok, response.statusCode);
    }
    return CachedResponseHeaders.fromBaseResponse(response);
  }

  static CachedResponseHeaders? fromCacheFiles(final CacheFiles cacheFiles) {
    try {
      if (cacheFiles.metadata.existsSync()) {
        final json = jsonDecode(cacheFiles.metadata.readAsStringSync());
        if (json is Map<String, dynamic>) {
          final headersFromJson = CachedResponseHeaders.fromJson(json['headers']);
          if (headersFromJson != null) return headersFromJson;
        }
      }
      return CachedResponseHeaders.fromFile(cacheFiles.complete);
    } catch (_) {
      return null;
    }
  }

  ///Simulates a [CachedResponseHeaders] object from the given [file].
  ///Returns null if the file does not exist or is empty.
  static CachedResponseHeaders? fromFile(final File file) {
    final fileStat = file.statSync();
    final fileSize = fileStat.size;
    if (fileStat.type != FileSystemEntityType.file || fileSize <= 0) {
      return null;
    }
    final contentTypeFromPath = MimeTypes.fromPath(file.path);

    final headers = {
      HttpHeaders.contentLengthHeader: fileSize.toString(),
      HttpHeaders.acceptRangesHeader: 'bytes',
      if (contentTypeFromPath != null) HttpHeaders.contentTypeHeader: contentTypeFromPath,
      HttpHeaders.lastModifiedHeader: HttpDate.format(fileStat.modified),
    };
    return CachedResponseHeaders._(headers);
  }

  static CachedResponseHeaders? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final Map<String, String> headers = {};

    json.forEach((key, value) {
      headers[key] = value is Iterable ? value.join(', ') : value.toString();
    });

    return CachedResponseHeaders._(headers);
  }

  Map<String, String> toJson() {
    return _headers;
  }

  void forEach(void Function(String, String) action) => _headers.forEach(action);

  Map<String, String> get headerMap => {..._headers};
}
