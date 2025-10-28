// This is a simple example of how to use the http_cache_stream package with a HLS video using a LazyCacheStream.

import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:video_player/video_player.dart';

class HLSVideoLazyCacheStreamExample extends StatefulWidget {
  final Uri sourceUrl;
  const HLSVideoLazyCacheStreamExample(this.sourceUrl, {super.key});

  @override
  State<HLSVideoLazyCacheStreamExample> createState() =>
      _HLSVideoLazyCacheStreamExampleState();
}

class _HLSVideoLazyCacheStreamExampleState
    extends State<HLSVideoLazyCacheStreamExample> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    final lazyCacheStream = HttpCacheManager.instance.createLazyStream(
      widget.sourceUrl,
    );
    final cacheUrl = lazyCacheStream.cacheUrl;

    print('Playing from: $cacheUrl');

    ///Important: Pass the request headers from lazyCacheStream to the VideoPlayerController
    final controller =
        _controller = VideoPlayerController.networkUrl(
          cacheUrl,
          httpHeaders: lazyCacheStream.requestHeader,
        );
    await controller.initialize();
    if (mounted) {
      setState(() {});
      controller.play();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}
