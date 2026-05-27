/// HexLoader — byte-stream loading animation (§5 Animation Concepts / §13 Loading States)
///
/// Rapidly cycles random hex characters that eventually "resolve" into data.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/typography.dart';

class HexLoader extends StatefulWidget {
  final List<String>? bootSequence;
  final bool showSequence;

  const HexLoader({
    super.key,
    this.bootSequence,
    this.showSequence = false,
  });

  @override
  State<HexLoader> createState() => _HexLoaderState();
}

class _HexLoaderState extends State<HexLoader> {
  static const _chars = '0123456789ABCDEF';
  final _rng = Random();
  Timer? _timer;
  Timer? _seqTimer;

  String _hexDisplay = '';
  int _seqIndex = 0;
  final List<String> _revealedLines = [];

  @override
  void initState() {
    super.initState();
    _startHexRain();
    if (widget.showSequence && widget.bootSequence != null) {
      _startSequence();
    }
  }

  void _startHexRain() {
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        _hexDisplay = List.generate(
          32,
          (_) => _chars[_rng.nextInt(_chars.length)],
        ).join(' ');
      });
    });
  }

  void _startSequence() {
    final seq = widget.bootSequence!;
    _seqTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      if (_seqIndex < seq.length) {
        setState(() => _revealedLines.add(seq[_seqIndex]));
        _seqIndex++;
      } else {
        _seqTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _seqTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rapid hex rain
        Text(
          _hexDisplay,
          style: SFTypography.terminal.copyWith(
            color: SFColors.textFaint,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.showSequence && _revealedLines.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...(_revealedLines.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                style: SFTypography.terminal.copyWith(
                  color: SFColors.success.withAlpha(200),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )),
        ],
      ],
    );
  }
}
