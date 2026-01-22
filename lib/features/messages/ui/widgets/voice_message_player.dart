import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'waveform_visualizer.dart';

/// A polished voice message player widget for displaying voice messages
/// in chat bubbles.
///
/// Features:
/// - Play/pause button
/// - Waveform visualization with progress
/// - Duration display (elapsed/total)
/// - Seek by tapping on waveform
/// - Playback speed control
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    required this.audioUrl,
    required this.durationMs,
    super.key,
    this.localPath,
    this.isOwnMessage = false,
    this.waveformData,
    this.onPlaybackStart,
    this.onPlaybackEnd,
  });

  /// URL of the audio file on the server
  final String audioUrl;

  /// Local file path (for offline playback)
  final String? localPath;

  /// Duration in milliseconds
  final int durationMs;

  /// Whether this is the user's own message (affects styling)
  final bool isOwnMessage;

  /// Pre-computed waveform data (if available)
  final List<double>? waveformData;

  /// Called when playback starts
  final VoidCallback? onPlaybackStart;

  /// Called when playback ends
  final VoidCallback? onPlaybackEnd;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  bool _isPlaying = false;
  final bool _isLoading = false;
  double _progress = 0;
  double _playbackSpeed = 1;
  Timer? _progressTimer;
  Duration _currentPosition = Duration.zero;

  late Duration _totalDuration;
  late List<double> _waveformData;

  @override
  void initState() {
    super.initState();
    _totalDuration = Duration(milliseconds: widget.durationMs);
    // Use provided waveform data or generate fake data
    _waveformData = widget.waveformData ?? generateFakeWaveform(50);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    if (_isLoading) return;

    setState(() {
      _isPlaying = !_isPlaying;

      if (_isPlaying) {
        widget.onPlaybackStart?.call();
        // Simulate playback progress (real impl would use audio player)
        _progressTimer = Timer.periodic(
          Duration(milliseconds: (100 / _playbackSpeed).round()),
          (_) {
            setState(() {
              _currentPosition += const Duration(milliseconds: 100);
              _progress =
                  _currentPosition.inMilliseconds /
                  _totalDuration.inMilliseconds;

              if (_progress >= 1.0) {
                _progress = 0.0;
                _currentPosition = Duration.zero;
                _isPlaying = false;
                _progressTimer?.cancel();
                widget.onPlaybackEnd?.call();
              }
            });
          },
        );
      } else {
        _progressTimer?.cancel();
        widget.onPlaybackEnd?.call();
      }
    });
  }

  void _seekTo(double position) {
    setState(() {
      _progress = position.clamp(0.0, 1.0);
      _currentPosition = Duration(
        milliseconds: (_totalDuration.inMilliseconds * _progress).round(),
      );
    });
  }

  void _cyclePlaybackSpeed() {
    setState(() {
      // Cycle through: 1x -> 1.5x -> 2x -> 1x
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Colors based on message ownership
    final primaryColor = widget.isOwnMessage
        ? Colors.white.withValues(alpha: 0.9)
        : AppTheme.primaryGreen;
    final secondaryColor = widget.isOwnMessage
        ? Colors.white.withValues(alpha: 0.4)
        : AppTheme.primaryGreen.withValues(alpha: 0.4);
    final textColor = widget.isOwnMessage
        ? Colors.white.withValues(alpha: 0.7)
        : AppTheme.getTextColor(context).withValues(alpha: 0.7);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primaryColor.withValues(
                  alpha: widget.isOwnMessage ? 0.2 : 0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(primaryColor),
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: primaryColor,
                      size: 28,
                    ),
            ),
          ),

          const SizedBox(width: 8),

          // Waveform and info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform
                PlaybackWaveformVisualizer(
                  amplitudes: _waveformData,
                  progress: _progress,
                  width: 180,
                  height: 28,
                  playedColor: primaryColor,
                  unplayedColor: secondaryColor,
                  onSeek: _seekTo,
                ),

                const SizedBox(height: 4),

                // Duration and speed indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Current time / Total time
                    Text(
                      _isPlaying || _progress > 0
                          ? _formatDuration(_currentPosition)
                          : _formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    // Playback speed button
                    GestureDetector(
                      onTap: _cyclePlaybackSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(
                            alpha: widget.isOwnMessage ? 0.2 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_playbackSpeed.toStringAsFixed(_playbackSpeed == 1.0 || _playbackSpeed == 2.0 ? 0 : 1)}x',
                          style: TextStyle(
                            fontSize: 10,
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact voice message player for list views or smaller contexts
class CompactVoiceMessagePlayer extends StatefulWidget {
  const CompactVoiceMessagePlayer({
    required this.audioUrl,
    required this.durationMs,
    super.key,
    this.localPath,
    this.isOwnMessage = false,
  });

  final String audioUrl;
  final String? localPath;
  final int durationMs;
  final bool isOwnMessage;

  @override
  State<CompactVoiceMessagePlayer> createState() =>
      _CompactVoiceMessagePlayerState();
}

class _CompactVoiceMessagePlayerState extends State<CompactVoiceMessagePlayer> {
  bool _isPlaying = false;
  double _progress = 0;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;

      if (_isPlaying) {
        final durationMs = widget.durationMs > 0 ? widget.durationMs : 1000;
        _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          setState(() {
            _progress += 100 / durationMs;
            if (_progress >= 1.0) {
              _progress = 0.0;
              _isPlaying = false;
              _progressTimer?.cancel();
            }
          });
        });
      } else {
        _progressTimer?.cancel();
      }
    });
  }

  String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).round();
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isOwnMessage
        ? Colors.white.withValues(alpha: 0.9)
        : AppTheme.primaryGreen;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play button
        GestureDetector(
          onTap: _togglePlayback,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: primaryColor.withValues(
                alpha: widget.isOwnMessage ? 0.2 : 0.1,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: primaryColor,
              size: 20,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Progress bar
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: primaryColor.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(primaryColor),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(widget.durationMs),
                style: TextStyle(
                  fontSize: 11,
                  color: primaryColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
