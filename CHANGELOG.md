## 0.1.0

* Added `StreamLifecycleConfig` to cache configuration — controls pause and dispose
  delays for inactive streams.

* Added `release()` method to `HttpCacheStream`. Once released, the stream pauses
  its ongoing download after `StreamLifecycleConfig.pauseDelay` and is fully disposed
  after `StreamLifecycleConfig.disposeDelay`. Calling `retain()` before disposal
  cancels the timers and resumes the download.
  The `dispose()` method retains its original behaviour (immediate disposal,
  bypassing lifecycle configuration).

* `HttpCacheServer` is now the recommended approach for any scenario involving
  multiple URLs from the same origin (HLS/DASH, playlists, CDN-hosted assets).
  `HttpCacheManager.createServer` returns an existing server by default when called
  with the same origin, so a single server instance can be shared application-wide.

---

BREAKING: `HttpCacheServer` changes:

* `HttpCacheServer.source` renamed to `HttpCacheServer.origin`. The field has always
  held only the origin (scheme+host+port), and the new name reflects that precisely.
  URLs with the same origin (e.g. `https://cdn.example.com/1.mp3` and
  `https://cdn.example.com/2.mp3`) are both handled by the same server.

* `HttpCacheServer.dispose()` renamed to `HttpCacheServer.close()`.

* `HttpCacheServer.isDisposed` renamed to `HttpCacheServer.isClosed`.

* `HttpCacheManager.createServer` parameter renamed from `source` to `origin`.
  `createServer` now returns an existing server for the same origin by default
  (`returnExisting: true`). Pass `returnExisting: false` to force a new server.

* `HttpCacheManager.getExistingServer` parameter renamed from `sourceUrl` to `origin`.

---

BREAKING: `HttpCacheManager.createServer` lifecycle changes:

* Removed `autoDisposeDelay` parameter. Configure stream lifecycle via
  `StreamLifecycleConfig` on the `StreamCacheConfig` passed to `createServer` instead:

  ```dart
  // Before
  await manager.createServer(source, autoDisposeDelay: Duration(seconds: 30));

  // After
  final config = manager.createStreamConfig();
  config.lifecycleConfig = StreamLifecycleConfig(
    pauseDelay: Duration(seconds: 10),
    disposeDelay: Duration(seconds: 30),
  );
  await manager.createServer(Uri.parse('https://cdn.example.com'), config: config);

## 0.0.7

* Renamed `InvalidCacheLengthException` to `InvalidCacheSizeException` and exposed expected/actual size.

## 0.0.6
* Add `onStreamCreated` callback to `HttpCacheManager`.

* Export exception types for easier package-specific error handling.

* Fix iOS cache server becoming unresponsive after resuming from background.

## 0.0.5 
* Add support for HTTP HEAD requests

* Add `cacheFileResolver` to global cache configuration. This function is used to determine the output cache file path when a stream is created.

* Add `requestTimeout` to cache configuration. Cache requests that are not fulfilled within this duration are closed with a `StreamRequestTimedOutException`. Defaults to 60 seconds.

* Fix broken links in example project

* Fix potential I/O exceptions

## 0.0.4
* Add `saveAllHeaders` to cache configuration. If false, only essential response headers are saved (defaults to true).

* Add `readTimeout` to cache configuration. Requests and responses that do not receive data within this duration are closed. Defaults to 30 seconds.

* Enhanced 'maxBufferSize' logic to close paused/unused response streams that exceed the specified buffer size.

* Breaking: requests exceeding `rangeRequestSplitThreshold` are automatically fulfilled without starting the cache download

* Improved response times and performance

## 0.0.3

* Add acceptRangesHeader to partial content response headers

## 0.0.2

* Added an experimental HttpCacheServer that automatically creates and disposes HttpCacheStream's for a specified source. This enables compatibility with dynamic URLs such as HLS streams. 

* Added the ability to use a custom http.dart client for all cache downloads. The client must be specified when initalizing the HttpCacheManager, either directly in the init function, or through a custom global cache config.

* Added getExistingStream and getExistingServer to HttpCacheManager to retrieve an existing cache stream or server, if it exists.

* Added preCacheUrl to HttpCacheManager to pre-cache a url

* Added the ability to supply cache config when initializing HttpCacheManager and creating cache streams (@MSOB7YY)

* Added onCacheDone callbacks to both global cache config and stream cache config (@MSOB7YY)

* Added savePartialCache and saveMetadata to cache config

* Added HLS video to example project.

* Improved cache response times by immediately fulfilling requests when possible

* Fixed an issue renaming cache file on Windows (@MSOB7YY)

* Fixed an issue that occurred when the cache stream attempted to read from the partial cache file after the cache download was completed. 

* Removed RxDart dependency. The progress stream now uses a standard broadcast controller, and will not emit the latest value to new listeners. However, the latest progress and error can still be obtained via cacheStream.progress and cacheStream.lastErrorOrNull.


## 0.0.1

* Initial release
