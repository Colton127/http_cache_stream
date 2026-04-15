// This is a simple example of how to use the http_cache_stream package with the video_player package.

import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream_example/widgets/cache_progress_bar.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerExample extends StatefulWidget {
  final Uri sourceUrl;
  const VideoPlayerExample(this.sourceUrl, {super.key});

  @override
  State<VideoPlayerExample> createState() => _VideoPlayerExampleState();
}

class _VideoPlayerExampleState extends State<VideoPlayerExample> {
  late final VideoPlayerController _controller;
  late final httpCacheStream = HttpCacheManager.instance.createStream(
    widget.sourceUrl,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    print('Playing from: ${httpCacheStream.cacheUrl}');
    _controller = VideoPlayerController.networkUrl(httpCacheStream.cacheUrl);
    await _controller.initialize();
    if (mounted) {
      setState(() {});
      _controller.play();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose().whenComplete(() {
      return httpCacheStream
          .dispose(); //Dispose the cache stream after the player is disposed
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controller.value.isInitialized
            ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
            : CircularProgressIndicator(),
        CacheProgressBar(httpCacheStream),
      ],
    );
  }
}
