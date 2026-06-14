/// Document Viewer Screen — RAM-only file display (§2)
///
/// Supports PDF (via SfPdfViewer.memory) and text files.
/// Decrypted bytes are never written to disk.
/// Auto-purges after 5 minutes and zeroes the buffer on close.
library;

import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/vault_file.dart';
import '../services/vault_provider.dart';
import '../widgets/panic_button.dart';
import '../widgets/tactical_label.dart';
import '../utils/logger.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  final VaultFile file;
  const DocumentViewerScreen({super.key, required this.file});

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  Uint8List? _decryptedBytes;
  bool _isPdf = false;
  String? _textContent;
  bool _isLoading = true;
  String? _error;

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
    sfLog('Viewer: opening "${widget.file.name}" source=${widget.file.source}');

    final cloudAsync = ref.read(cloudServiceProvider);
    final cloud = cloudAsync.valueOrNull;
    sfLog('Viewer: cloudService=${cloud == null ? "NULL" : "OK"}');
    if (cloud == null) {
      setState(() {
        _error = 'CLOUD NOT CONFIGURED\nGo to Settings → CONFIGURE AWS CREDENTIALS\nand fill in all 4 AWS fields + the Desktop Vault Secret.';
        _isLoading = false;
      });
      return;
    }

    final crypto = ref.read(cryptoServiceProvider);
    sfLog('Viewer: crypto.isUnlocked=${crypto.isUnlocked} mode=${crypto.handshakeMode}');
    if (!crypto.isUnlocked) {
      setState(() {
        _error = 'VAULT LOCKED\nGo back to the home screen and authenticate with biometric first.';
        _isLoading = false;
      });
      return;
    }

    try {
      sfLog('Viewer: downloading ${widget.file.name} from S3...');
      // Download encrypted blob directly into RAM — never touches disk.
      final encryptedBlob = await cloud.downloadToBuffer(widget.file.name);
      sfLog('Viewer: downloaded ${encryptedBlob.length}B, header=${encryptedBlob.length >= 4 ? String.fromCharCodes(encryptedBlob.sublist(0, 4)) : "TOO_SHORT"}');

      // Decrypt in RAM using the loaded master secret.
      sfLog('Viewer: decrypting...');
      final plain = crypto.decryptBlob(encryptedBlob);
      sfLog('Viewer: decrypted ${plain.length}B successfully');

      // Detect PDF by magic bytes %PDF
      final isPdf = plain.length >= 4 &&
          plain[0] == 0x25 && // %
          plain[1] == 0x50 && // P
          plain[2] == 0x44 && // D
          plain[3] == 0x46;   // F
      sfLog('Viewer: isPdf=$isPdf');

      String? text;
      if (!isPdf) {
        // Try UTF-8 text decode; fall back to showing binary info.
        try {
          text = String.fromCharCodes(plain);
        } catch (_) {
          text = null;
        }
      }

      setState(() {
        _decryptedBytes = plain;
        _isPdf = isPdf;
        _textContent = text;
        _isLoading = false;
      });
    } catch (e) {
      sfLog('Viewer: ERROR — $e');
      setState(() {
        _error = 'DECRYPT FAILED\n$e';
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
    // Zero-fill decrypted bytes before releasing reference (best-effort).
    _decryptedBytes?.fillRange(0, _decryptedBytes!.length, 0);
    _decryptedBytes = null;
    _textContent = null;
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
    // Zero-fill before GC to prevent cold-boot attacks.
    _decryptedBytes?.fillRange(0, _decryptedBytes!.length, 0);
    super.dispose();
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
                            Row(children: [
                              const TacticalLabel(SFCopy.ramOnly,
                                  color: SFColors.success, fontSize: 9),
                              if (!_isLoading && _error == null) ...[
                                const SizedBox(width: 8),
                                TacticalLabel(
                                  _isPdf ? 'PDF' : 'TEXT',
                                  color: SFColors.textFaint,
                                  fontSize: 9,
                                ),
                              ],
                            ]),
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
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(
                          strokeWidth: 1, color: SFColors.textMuted))
                      : _error != null
                          ? _ErrorView(error: _error!)
                          : _isPdf && _decryptedBytes != null
                              ? _PdfView(bytes: _decryptedBytes!)
                              : _TextView(
                                  text: _textContent,
                                  byteCount: _decryptedBytes?.length ?? 0,
                                ),
                ),

                // ── Close file button ────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(SFSpacing.base),
                  child: PanicButton(
                    label: SFCopy.panicClose,
                    icon: Icons.close,
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
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _PdfView extends StatelessWidget {
  final Uint8List bytes;
  const _PdfView({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return SfPdfViewer.memory(
      bytes,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      enableDoubleTapZooming: true,
    );
  }
}

class _TextView extends StatelessWidget {
  final String? text;
  final int byteCount;
  const _TextView({this.text, required this.byteCount});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SFSpacing.base),
      child: Text(
        text ?? '[BINARY DATA — $byteCount BYTES]\n\nThis file is not a text file. It may be an image or other binary format.',
        style: SFTypography.terminal.copyWith(
          color: text != null ? SFColors.textMuted : SFColors.textFaint,
          height: 1.7,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SFSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 32, color: SFColors.danger),
            const SizedBox(height: SFSpacing.md),
            Text(
              error,
              style: SFTypography.terminal.copyWith(color: SFColors.danger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SFSpacing.md),
            Text(
              'Ensure the vault is unlocked and your desktop\nsecret is configured in Settings.',
              style: SFTypography.bodyMuted.copyWith(fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Watermark ────────────────────────────────────────────────────────────────

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
