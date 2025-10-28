// This is a simple example of how to use the http_cache_stream package with a HLS video using HttpCacheServer.

import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:video_player/video_player.dart';

class HLSVideoCacheServerExample extends StatefulWidget {
  final Uri sourceUrl;
  const HLSVideoCacheServerExample(this.sourceUrl, {super.key});

  @override
  State<HLSVideoCacheServerExample> createState() =>
      _HLSVideoCacheServerExampleState();
}

class _HLSVideoCacheServerExampleState
    extends State<HLSVideoCacheServerExample> {
  VideoPlayerController? _controller;
  HttpCacheServer? _cacheServer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    final sourceUrl = widget.sourceUrl;
    final source = Uri(
      host: sourceUrl.host,
      port: sourceUrl.port,
      scheme: sourceUrl.scheme,
    );
    final cacheServer =
        _cacheServer = await HttpCacheManager.instance.createServer(source);
    if (!mounted) {
      cacheServer.dispose();
      return;
    }
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
    _cacheServer?.dispose();
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
