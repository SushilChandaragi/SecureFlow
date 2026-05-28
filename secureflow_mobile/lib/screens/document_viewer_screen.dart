/// Document Viewer Screen — RAM-only file display (§2)
library;

import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/vault_file.dart';
import '../services/vault_provider.dart';
import '../widgets/panic_button.dart';
import '../widgets/tactical_label.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  final VaultFile file;
  const DocumentViewerScreen({super.key, required this.file});

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

enum _ViewerKind { pdf, image, text, binary }

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  Uint8List? _decryptedBytes;
  String? _textContent;
  bool _isLoading = true;
  String? _error;
  _ViewerKind _viewerKind = _ViewerKind.binary;
  // 5-minute auto-purge countdown
  late int _purgeSeconds;
  Timer? _purgeTimer;

  @override
  void initState() {
    super.initState();
    _purgeSeconds = 300;
    _loadAndDecrypt();
    _startPurgeTimer();
  }

  Future<void> _loadAndDecrypt() async {
    final cloudAsync = ref.read(cloudServiceProvider);
    final cloud = cloudAsync.valueOrNull;
    if (cloud == null) {
      setState(() {
        _error = 'CLOUD NOT CONFIGURED';
        _isLoading = false;
      });
      return;
    }
    final crypto = ref.read(cryptoServiceProvider);
    try {
      final blob = await cloud.downloadToBuffer(widget.file.name);
      final plain = crypto.decryptBlob(blob);
      final kind = _detectViewerKind(plain, widget.file.displayName);
      String? text;
      if (kind == _ViewerKind.text) {
        try {
          text = String.fromCharCodes(plain);
        } catch (_) {
          text = null;
        }
      }
      setState(() {
        _decryptedBytes = plain;
        _textContent = text;
        _viewerKind = text == null && kind == _ViewerKind.text ? _ViewerKind.binary : kind;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _startPurgeTimer() {
    _purgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _purgeSeconds--);
      if (_purgeSeconds <= 0) _panicClose();
    });
  }

  void _panicClose() {
    // Zero fill decrypted bytes
    _decryptedBytes?.fillRange(0, _decryptedBytes!.length, 0);
    _decryptedBytes = null;
    _textContent = null;
    _viewerKind = _ViewerKind.binary;
    _purgeTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  String get _purgeCountdown {
    final m = (_purgeSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_purgeSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _purgeTimer?.cancel();
    _decryptedBytes?.fillRange(0, _decryptedBytes!.length, 0);
    _decryptedBytes = null;
    super.dispose();
  }

  _ViewerKind _detectViewerKind(Uint8List bytes, String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return _ViewerKind.pdf;
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp')) {
      return _ViewerKind.image;
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.json') || lower.endsWith('.xml')) {
      return _ViewerKind.text;
    }

    final mime = lookupMimeType(lower, headerBytes: bytes);
    if (mime != null) {
      if (mime == 'application/pdf') return _ViewerKind.pdf;
      if (mime.startsWith('image/')) return _ViewerKind.image;
      if (mime.startsWith('text/')) return _ViewerKind.text;
    }

    if (_looksLikePdf(bytes)) return _ViewerKind.pdf;
    if (_looksLikePng(bytes) || _looksLikeJpeg(bytes)) return _ViewerKind.image;

    return _ViewerKind.binary;
  }

  bool _looksLikePdf(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  }

  bool _looksLikePng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
  }

  bool _looksLikeJpeg(Uint8List bytes) {
    return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // RAM-ONLY diagonal watermark
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _WatermarkPainter()),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(SFSpacing.base),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _panicClose,
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: SFColors.textMuted, size: 18),
                      ),
                      const SizedBox(width: SFSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TacticalLabel(widget.file.displayName,
                                color: SFColors.textMuted),
                            const TacticalLabel(SFCopy.ramOnly,
                                color: SFColors.success, fontSize: 9),
                          ],
                        ),
                      ),
                      // Auto-purge countdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: _purgeSeconds < 60
                              ? SFColors.danger : SFColors.borderSoft),
                          borderRadius: BorderRadius.circular(SFRadius.small),
                        ),
                        child: Text(
                          _purgeCountdown,
                          style: SFTypography.terminal.copyWith(
                            color: _purgeSeconds < 60
                                ? SFColors.danger : SFColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: SFColors.borderSoft),

                // ── Content ───────────────────────────────────────
                Expanded(
                  child: _buildContent(),
                ),

                // ── Panic close button ────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(SFSpacing.base),
                  child: PanicButton(
                    label: SFCopy.panicClose,
                    icon: Icons.bolt,
                    onPressed: _panicClose,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.textMuted),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: SFTypography.terminal.copyWith(color: SFColors.danger),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_decryptedBytes == null) {
      return Center(
        child: Text(
          'NO DATA IN MEMORY',
          style: SFTypography.terminal.copyWith(color: SFColors.textMuted),
        ),
      );
    }

    switch (_viewerKind) {
      case _ViewerKind.pdf:
        return SfPdfViewer.memory(_decryptedBytes!);
      case _ViewerKind.image:
        return Center(
          child: InteractiveViewer(
            child: Image.memory(_decryptedBytes!, fit: BoxFit.contain),
          ),
        );
      case _ViewerKind.text:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(SFSpacing.base),
          child: Text(
            _textContent ?? '[TEXT UNAVAILABLE]',
            style: SFTypography.terminal.copyWith(
              color: SFColors.textMuted,
              height: 1.7,
            ),
          ),
        );
      case _ViewerKind.binary:
      default:
        return Center(
          child: Text(
            '[BINARY DATA — ${_decryptedBytes?.length ?? 0} BYTES]',
            style: SFTypography.terminal.copyWith(color: SFColors.textMuted),
            textAlign: TextAlign.center,
          ),
        );
    }
  }
}

class _WatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'RAM-ONLY SESSION',
        style: TextStyle(
          fontSize: 14,
          letterSpacing: 4,
          color: Colors.white.withAlpha(6),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.4); // Diagonal slant

    const spacing = 120.0;
    for (double y = -size.height; y < size.height * 2; y += spacing) {
      for (double x = -size.width; x < size.width * 2; x += 280) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_) => false;
}
