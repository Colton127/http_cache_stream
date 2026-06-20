//Example of how to use the just_audio package (https://pub.dev/packages/just_audio) to play audio files by manually creating a cache stream.

import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream_example/widgets/cache_progress_bar.dart';
import 'package:http_cache_stream_example/widgets/seek_bar.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

class JustAudioExample extends StatefulWidget {
  final Uri sourceUrl;
  const JustAudioExample(this.sourceUrl, {super.key});

  @override
  State<JustAudioExample> createState() => _JustAudioExampleState();
}

class _JustAudioExampleState extends State<JustAudioExample> {
  final _player = AudioPlayer();
  late final httpCacheStream = HttpCacheManager.instance.createStream(
    widget.sourceUrl,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    _setRangeThreshold();
    final cachedUrl = httpCacheStream.cacheUrl;
    final audioSource = AudioSource.uri(httpCacheStream.cacheUrl);
    _player.setAudioSource(audioSource);
    print('Playing from: $cachedUrl');
  }

  void _setRangeThreshold() {
    ///Test using a range request split threshold of 5MB
    httpCacheStream.config.rangeRequestSplitThreshold = 1024 * 1024 * 5; // 5MB
  }

  @override
  void dispose() {
    super.dispose();
    httpCacheStream
        .release(); //Release the cache stream when the widget is disposed.
    _player.dispose();
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Display play/pause button and volume/speed sliders.
        ControlButtons(_player),
        // Display seek bar. Using StreamBuilder, this widget rebuilds
        // each time the position, buffered position or duration changes.
        StreamBuilder<PositionData>(
          stream: _positionDataStream,
          builder: (context, snapshot) {
            final positionData = snapshot.data;
            return SeekBar(
              duration: positionData?.duration ?? Duration.zero,
              position: positionData?.position ?? Duration.zero,
              bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
              onChangeEnd: _player.seek,
            );
          },
        ),
        CacheProgressBar(httpCacheStream),
      ],
    );
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;
  const ControlButtons(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final playing = playerState?.playing;
        if (processingState == ProcessingState.loading ||
            processingState == ProcessingState.buffering) {
          return Container(
            margin: const EdgeInsets.all(8.0),
            width: 64.0,
            height: 64.0,
            child: const CircularProgressIndicator(),
          );
        } else if (playing != true) {
          return IconButton(
            icon: const Icon(Icons.play_arrow),
            iconSize: 64.0,
            onPressed: player.play,
          );
        } else if (processingState != ProcessingState.completed) {
          return IconButton(
            icon: const Icon(Icons.pause),
            iconSize: 64.0,
            onPressed: player.pause,
          );
        } else {
          return IconButton(
            icon: const Icon(Icons.replay),
            iconSize: 64.0,
            onPressed: () => player.seek(Duration.zero),
          );
        }
      },
    );
  }
}
