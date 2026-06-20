A Flutter package that simultaneously downloads, caches, and streams remote content. Perfect for media players and any plugin that streams web content.


# Motivation

The ability to simultaneously download and cache files remains a highly requested feature of video and audio playback plugins. 
By creating a local HTTP server, HttpCacheStream supports virtually any plugin that streams from web links. Unlike traditional caching solutions, HttpCacheStream works while the file is still downloading - allowing immediate playback of media files. 

### Features
- Simultaneous Download and Streaming - Start playing media instantly while downloading
- Persistent Caching - Cache files locally for offline playback
- Range Request Support - Efficient seeking in media players
- Resumable Downloads - Continue downloads after app restart
- HTTP Server - Works with any media player supporting HTTP URLs
- Custom Headers - Configure both request and response headers


# Getting Started
Using http_cache_stream to simultaneously cache and stream a video file:

```dart
import 'package:http_cache_stream/http_cache_stream.dart';

// Initialize the cache manager once, at app startup
await HttpCacheManager.init();

// Get a local cache URL for any remote resource
final sourceUrl = Uri.parse('https://example.com/video.mp4');
final cacheUrl = HttpCacheManager.instance.getCacheUrl(sourceUrl);
// Example output: http://127.0.0.1:4612/example.com/video.mp4

// Pass it directly to your media player
final videoPlayerController = VideoPlayerController.networkUrl(cacheUrl);
await videoPlayerController.initialize();
videoPlayerController.play();
```

The cache stream is created and managed automatically — no lifecycle management required. For direct access to the `HttpCacheStream` instance (e.g., to monitor download progress or configure per-stream settings), use `createStream` instead. See [HttpCacheStream](#httpcachestream) below.

See the example project to learn how to use http_cache_stream with [video_player](https://pub.dev/packages/video_player), [audioplayers](https://pub.dev/packages/audioplayers), and [just_audio](https://pub.dev/packages/just_audio)

## Platform configuration

Since http_cache_stream utilizes a localhost HTTP server, configuration is necessary to allow cleartext (non-HTTPS) connections:

### iOS/macOS

Add the following to your projects `Info.plist` file:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Android:

Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
	<domain-config cleartextTrafficPermitted="true">
		<domain includeSubdomains="false">127.0.0.1</domain>
	</domain-config>
</network-security-config>
```

Reference the file in `android/app/src/main/res/AndroidManifest.xml` by adding the following entry under `application`:

```xml
    <application ... android:networkSecurityConfig="@xml/network_security_config">
```

See the example project for a full example.


# Core Components

## HttpCacheManager

The central manager for all cache streams:

```dart
// Initialize once, at app startup
await HttpCacheManager.init();
final cacheManager = HttpCacheManager.instance;

// Get a cache URL — the recommended way to integrate with media players
final cacheUrl = cacheManager.getCacheUrl(sourceUrl);

// Pre-cache files:
await cacheManager.preCacheUrl(Uri.parse('https://example.com/file.mp3'));

// Configure global settings
cacheManager.config.requestHeaders[HttpHeaders.userAgentHeader] = 'MyApp/1.0';

// Delete inactive cache files
await cacheManager.deleteCache();
```

## HttpCacheStream

Provides direct access to the download, cache, and streaming state for a specific URL. Use `createStream` when you need to monitor progress or configure per-stream settings.

```dart
final cacheStream = cacheManager.createStream(Uri.parse('https://example.com/file.mp3'));

// Start download explicitly (optional — begins automatically on first request)
cacheStream.download();

// Monitor CacheState for position and source length
cacheStream.cacheStateStream.listen((state) {
  print('${state.position} / ${state.sourceLength} bytes');
});

// Release when done — the stream will be paused and eventually disposed
// automatically according to StreamLifecycleConfig.
// Call dispose() instead to tear down immediately.
cacheStream.release();
```


## CacheMetadata
Each cached file has associated metadata stored in a companion .metadata file, which contains:

- Original source URL
- Response headers from the server
- Additional cache information

```dart
// Get metadata for all cached files
final allMetadata = await cacheManager.cacheMetadataList();
final activeOnly = await cacheManager.cacheMetadataList(active: true);
final inactiveOnly = await cacheManager.cacheMetadataList(active: false);

// Get metadata for a specific URL
final metadata = cacheManager.getCacheMetadata(Uri.parse('https://example.com/video.mp4'));

// Delete cache files
await metadata?.cacheFiles.delete();
```

Metadata is automatically managed by HttpCacheStream, but you can also work with it directly to inspect or manipulate the cache without creating stream instances.



# Advanced Usage

### Cache Configuration

Configure both global and per-stream settings:
```dart
// Global configuration
final globalConfig = HttpCacheManager.instance.config;
globalConfig.requestHeaders[HttpHeaders.userAgentHeader] = 'MyApp/1.0';

// Per-stream configuration
final cacheStream = cacheManager.createStream(Uri.parse('https://example.com/file.mp3'));
cacheStream.config.copyCachedResponseHeaders = true;
```


### Stream Lifecycle

When `createStream` is used, call `release()` instead of `dispose()` to hand the stream back to the cache manager. The behavior after release is controlled by `StreamLifecycleConfig`:

```dart
// Configure globally (applies to all streams)
HttpCacheManager.instance.config.lifecycleConfig = StreamLifecycleConfig(
  pauseAfter: Duration(seconds: 10),   // Pause the download after 10s of inactivity
  disposeAfter: Duration(minutes: 5),  // Fully dispose the stream after 5 minutes
);
```

Call `dispose()` to tear down a stream immediately, bypassing the lifecycle configuration.


### Range Request Controls
When a client requests a byte range that's significantly ahead of what's currently cached, the library can initiate a separate direct connection to the source, rather than waiting for the sequential cache download to reach that position. The `rangeRequestSplitThreshold` setting controls this behavior by defining how many bytes ahead a request must be to trigger a separate connection.

```dart
// Set the threshold for creating a split download (in bytes)
cacheStream.config.rangeRequestSplitThreshold = 5 * 1024 * 1024; // 5MB

// Disable split downloads
cacheStream.config.rangeRequestSplitThreshold = null;
```

### Cache Validation

```dart
// Check if cache is still valid
final isValid = await cacheStream.validateCache();
if (isValid == false) {
  // Cache is invalid, reset it
  await cacheStream.resetCache();
}

// Enable automatic validation of outdated cache
cacheStream.config.validateOutdatedCache = true;
```

## Credits

http_cache_stream began as a custom implementation of [just_audio](https://pub.dev/packages/just_audio)'s `LockCachingAudioSource`, a feature enabling simultaneous streaming and caching of audio files. Many thanks goes out to the developer and contributors of just_audio.

