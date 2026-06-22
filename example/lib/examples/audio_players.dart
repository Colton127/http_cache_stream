//Example of how to use the audioplayers package (https://pub.dev/packages/audioplayers) to play audio files

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http_cache_stream/http_cache_stream.dart';
import 'package:http_cache_stream_example/widgets/seek_bar.dart';
import 'package:rxdart/rxdart.dart';

class AudioPlayersExample extends StatefulWidget {
  final Uri sourceUrl;
  const AudioPlayersExample(this.sourceUrl, {super.key});

  @override
  State<AudioPlayersExample> createState() => _AudioPlayersExampleState();
}

class _AudioPlayersExampleState extends State<AudioPlayersExample> {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    final cachedUrl = HttpCacheManager.instance.getCacheUrl(widget.sourceUrl);
    print('Playing from: $cachedUrl');
    _player.play(UrlSource(cachedUrl.toString()));
  }

  @override
  void dispose() {
    super.dispose();
    _player.dispose();
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest2<Duration, Duration, PositionData>(
        _player.onPositionChanged,
        _player.onDurationChanged,
        (position, duration) => PositionData(position, position, duration),
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
      stream: player.onPlayerStateChanged,
      builder: (context, snapshot) {
        final playerState = snapshot.data ?? player.state;
        switch (playerState) {
          case PlayerState.playing:
            return IconButton(
              icon: const Icon(Icons.pause),
              iconSize: 64.0,
              onPressed: player.pause,
            );
          case PlayerState.paused || PlayerState.stopped:
            return IconButton(
              icon: const Icon(Icons.play_arrow),
              iconSize: 64.0,
              onPressed: player.resume,
            );
          case PlayerState.completed:
            return IconButton(
              icon: const Icon(Icons.replay),
              iconSize: 64.0,
              onPressed: () => player.seek(Duration.zero),
            );
          case PlayerState.disposed:
            throw UnimplementedError();
        }
      },
    );
  }
}
