## 0.0.4

### Added
- `HttpCacheManager.createLazyStream()` - Creates a lazy-loading cache stream that automatically manages `HttpCacheStream` lifecycle
  - Streams are created on-demand when first requested
  - Automatically disposed after `StreamCacheConfig.autoDisposeDelay` when no active requests remain
  - Supports redirects when using `LazyCacheStream.requestHeader` to make requests (e.g., m3u8 files).
  - Accepts optional `file`, and `config`, parameters

* Breaking: Removed cacheDir and customHttpClient parameters in HttpCacheManager.init(). To specify a custom cache directory and/or http client, provide a GlobalCacheConfig during initalization. (See GlobalCacheConfig.init)

* Breaking: Removed autoDisposeDelay parameter in `HttpCacheManager.createServer()`. Use `StreamCacheConfig.autoDisposeDelay` instead.

* Added an optional 'cacheFileResolver' to GlobalCacheConfig. When provided, the resolver is used by the manager to generate cache file paths instead of the default path generation

* Improved cache I/O write performance by immediately writing data to file system

* Improved cache download time by buffering data while processing requests.

* Added an optional port parameter to HttpCacheManager.init and HttpCacheManager.createServer to specify the cache server port instead of using a random available port.

* Adjust default minChunkSize to 128KB and rangeRequestSplitThreshold to 5MB for improved cache stream performance and responsiveness.

* Update example project with HLS video using LazyCacheStream


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
