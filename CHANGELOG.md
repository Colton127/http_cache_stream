## 0.0.5
* Add support for HTTP HEAD requests

* `HttpCacheServer` is no longer considered experimental. 

* Add `cacheFileResolver` callback to `GlobalCacheConfig`.

* Add `serverConfig` parameter to `HttpCacheManager.init` and `HttpCacheManager.createServer`. Provide a `CacheServerConfig` to customize the address and port the cache server uses.

* Add `retryDelay` to cache configuration to specify the delay between retrying downloads.

* Fix potential race condition when modifying cache files

* Queued requests that exceed `readTimeout` are now completed with a `ResponseTimedOutException`.

* Depreciate `cacheDir` and `customHttpClient` parameters in HttpCacheManager.init(). Provide a `GlobalCacheConfig` to set these values.

* Ensure cache directory exists before writing cache files

* Improve exception types/models


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
