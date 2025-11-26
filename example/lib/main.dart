import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream_example/examples/audio_players.dart';
import 'package:http_cache_stream_example/examples/hls_video_cache_server.dart';
import 'package:http_cache_stream_example/examples/just_audio.dart';
import 'package:http_cache_stream_example/examples/pre_cache_url.dart';
import 'package:http_cache_stream_example/examples/video_player.dart';

import 'examples/hls_video_lazy_cache_stream.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    final bool initialized = HttpCacheManager.isInitialized;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                children: [
                  if (initialized) _Body(),
                  OutlinedButton(
                    onPressed: () async {
                      if (initialized) {
                        HttpCacheManager.instance.dispose();
                      } else {
                        final config = await GlobalCacheConfig.init();
                        config.autoDisposeDelay = const Duration(
                          hours: 24,
                        ); //Test
                        await HttpCacheManager.init(config: config);
                      }
                      setState(() {});
                    },
                    child: Text(initialized ? 'Stop' : 'Start'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BuildButton(
          'audioplayers',
          AudioPlayersExample(
            Uri.parse(
              'https://dovetail.prxu.org/70/66673fd4-6851-4b90-a762-7c0538c76626/CoryCombs_2021T_VO_Intro.mp3',
            ),
          ),
        ),
        _BuildButton(
          'just_audio',
          JustAudioExample(
            Uri.parse(
              'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
            ),
          ),
        ),
        _BuildButton(
          'video_player',
          VideoPlayerExample(
            Uri.parse(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
            ),
          ),
        ),
        _BuildButton(
          'HLS Video - CacheServer',
          HLSVideoCacheServerExample(
            Uri.parse('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
          ),
        ),
        _BuildButton(
          'HLS Video - LazyCacheStream',
          HLSVideoLazyCacheStreamExample(
            Uri.parse('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
          ),
        ),
        _BuildButton(
          'Pre-Cache URL',
          PreCacheUrl(
            Uri.parse(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
            ),
          ),
        ),
        Divider(),
        OutlinedButton(
          onPressed: () {
            HttpCacheManager.instance.deleteCache(partialOnly: false);
          },
          child: Text('Delete Cache'),
        ),

        Divider(),
      ],
    );
  }
}

class _BuildButton extends StatefulWidget {
  final String label;
  final Widget child;
  const _BuildButton(this.label, this.child);

  @override
  State<_BuildButton> createState() => __BuildButtonState();
}

class __BuildButtonState extends State<_BuildButton> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () {
            setState(() {
              _enabled = !_enabled;
            });
          },
          child: Text(
            _enabled ? 'Close ${widget.label}' : 'Build ${widget.label}',
          ),
        ),
        if (_enabled) widget.child,
      ],
    );
  }
}
