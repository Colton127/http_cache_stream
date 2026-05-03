// This is a simple example of how to use the http_cache_stream package with a HLS video.

import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:video_player/video_player.dart';

class HLSVideoExample extends StatefulWidget {
  final Uri sourceUrl;
  const HLSVideoExample(this.sourceUrl, {super.key});

  @override
  State<HLSVideoExample> createState() => _VideoPlayerExampleState();
}

class _VideoPlayerExampleState extends State<HLSVideoExample> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    final sourceUrl = widget.sourceUrl;
    final cacheServer = await HttpCacheManager.instance.createServer(sourceUrl);
    if (!mounted) return;

    final cacheUrl = cacheServer.getCacheUrl(sourceUrl);
    print('Playing from: $cacheUrl');
    final controller = _controller = VideoPlayerController.networkUrl(cacheUrl);
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
    return AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller));
  }
}
