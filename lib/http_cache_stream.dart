/// A Flutter package that simultaneously downloads, caches, and streams remote content.
///
/// By creating a local HTTP server, `http_cache_stream` supports virtually any
/// plugin that streams from web links. Unlike traditional caching solutions,
/// it works while the file is still downloading - allowing immediate playback
/// of media files.
///
/// Features:
/// * Simultaneous download and streaming
/// * Persistent caching for offline playback
/// * Range request support (seeking)
/// * Resumable downloads
/// * Custom header configuration
library;

export 'src/cache_manager/http_cache_manager.dart';
export 'src/cache_server/http_cache_server.dart';
export 'src/cache_stream/http_cache_stream.dart';
export 'src/models/cache_config/cache_config.dart';
export 'src/models/cache_config/global_cache_config.dart';
export 'src/models/cache_config/stream_cache_config.dart';
export 'src/models/cache_files/cache_file_type.dart';
export 'src/models/cache_files/cache_files.dart';
export 'src/models/cache_files/cache_file_resolver.dart';
export 'src/models/exceptions/http_exceptions.dart';
export 'src/models/exceptions/invalid_cache_exceptions.dart';
export 'src/models/exceptions/state_errors.dart';
export 'src/models/exceptions/stream_response_exceptions.dart';
export 'src/models/http_range/http_range.dart';
export 'src/models/http_range/http_range_request.dart';
export 'src/models/http_range/http_range_response.dart';
export 'src/models/metadata/cache_metadata.dart';
export 'src/models/metadata/cached_response_headers.dart';
export 'src/models/stream_requests/int_range.dart';
export 'src/models/stream_response/stream_response.dart';
