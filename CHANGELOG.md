## 0.0.4
* **Feat**: Add support for `HEAD` requests.
* **Feat**: Add `cacheRequestTimeout` to cache configuration. Requests that are not completed within this duration are closed with a TimeoutException.
* **Feat**: Add `retryDelay` to cache configuration to adjust delay between download retries.
* **Feat**: Add `saveAllHeaders` to cache configuration (defaults to `true`).
* **Perf**: Reduced request response time during download
* **Perf**: Reduced memory consumption
* **Fix**: Improve handling of generic content types.
* **Fix**: Improve general error handling.

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
