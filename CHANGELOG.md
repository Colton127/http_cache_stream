## 0.2.1

### New Features

* Added `HttpCacheManager.ensureActive()`. Ensures the local cache server is accepting connections, restarting it on the same port if needed. Call it before retrying a cache URL request that failed to connect (e.g. after an iOS app resumes from background suspension).

### Fixes

* Fixed the iOS local cache server staying unreachable after the app resumes from background suspension. Recovery previously re-attached to the same dead listening socket, so connections kept failing with "could not connect to server" (`-1004`). The server now releases the dead socket and binds a new one on the same port.

## 0.2.0

This release is designed to preserve existing behavior while making caching and streaming faster and more robust.

### Improvements

* Improved streaming performance and efficiency when serving cached content.
* Improved reliability when resuming partially downloaded files.
* Improved handling of interrupted downloads, cache validation, and source changes.
* Improved range request handling and cache integrity checks.
* Improved cache lifecycle and cleanup behavior across platforms.

### Fixes

* Fixed edge cases that could cause incomplete or outdated cached data to be served.
* Fixed several issues involving partial downloads, interrupted connections, and cache file transitions.
* Fixed assorted range request and local cache server edge cases.

## 0.1.0

This release significantly simplifies cache management. A new `getCacheUrl` API automates the full lifecycle of cache streams, eliminating the need to create or manage `HttpCacheStream` instances for most integrations.

### Breaking Changes

- **`HttpCacheServer` has been removed.** Use `HttpCacheManager.getCacheUrl` instead. It covers all previous use cases, including HLS/DASH and other dynamic URL patterns, with full lifecycle automation.
- **`InvalidCacheLengthException` has been renamed to `InvalidCacheSizeException`**, which now exposes the expected and actual cache size.

### New Features

**`HttpCacheManager`**

- Added `getCacheUrl(Uri sourceUrl)`. Returns a local cache URL that can be passed directly to any media player. Cache streams are created lazily on first request and their lifecycle is managed automatically by the cache manager.
- Added an optional `port` parameter to `HttpCacheManager.init`. Specifying a custom port allows cache urls to work across app restarts.

**`HttpCacheStream`**

- Added `release()`. Hands the stream back to the cache manager for lifecycle-managed teardown, governed by `StreamLifecycleConfig`. Use `release()` in place of `dispose()` when the stream may be reused. `dispose()` continues to work as before and bypasses the lifecycle configuration.
- Added `CacheState`, a richer alternative to the plain progress value. It tracks both the current cache position (bytes on disk) and the total source length. Access the latest snapshot via `cacheStream.cacheState`, or subscribe to changes via `cacheStream.cacheStateStream`.
- Added `StreamLifecycleConfig` to `CacheConfiguration`. Controls the inactive-stream behavior applied after `release()` is called. By default: downloads are paused after 10 seconds of inactivity, cancelled after the configured `readTimeout`, and the stream is fully disposed after 5 minutes.

### Improvements

- Cache headers are now read using async I/O.

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
