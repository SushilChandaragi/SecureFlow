/// Document Vault Screen — local encrypted document store with auto-cloud-sync
///
/// All documents are:
///   • Encrypted with AES-256-GCM before being stored to SQLite
///   • Decrypted in RAM only when opened (zero disk footprint)
///   • Automatically synced to S3 in the background after each add
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../models/vault_document.dart';
import '../models/vault_file.dart';
import '../services/vault_provider.dart';
import '../widgets/tactical_label.dart';
import 'cloud_vault_screen.dart';

// ─── Main Screen ─────────────────────────────────────────────────────────────

class DocumentVaultScreen extends ConsumerStatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  ConsumerState<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends ConsumerState<DocumentVaultScreen> {
  bool _uploading = false;
  bool _showCloud = false;

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    
    // Check cloud configured
    final cloud = ref.read(cloudServiceProvider).valueOrNull;
    if (cloud == null) {
      _showSnack('CLOUD NOT CONFIGURED — ADD AWS CREDENTIALS IN SETTINGS', isError: true);
      return;
    }

    // Pick file
    final result = await FilePicker.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      _showSnack('COULD NOT READ FILE BYTES', isError: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final crypto = ref.read(cryptoServiceProvider);
      final encrypted = crypto.isUnlocked
          ? crypto.encryptToBlob(bytes)
          : bytes;

      await cloud.uploadVaultFile(encrypted, file.name);

      // Refresh the file list
      ref.invalidate(vaultFilesProvider);
      
      _showSnack('UPLOADED: ${file.name}');
    } catch (e) {
      _showSnack('UPLOAD FAILED: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildTabSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: SFColors.bgCard,
          borderRadius: BorderRadius.circular(SFRadius.small),
          border: Border.all(color: SFColors.borderSoft),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTabButton(
                label: 'LOCAL SECURE STORAGE',
                isActive: !_showCloud,
                onTap: () => setState(() => _showCloud = false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildTabButton(
                label: 'CLOUD S3 STORAGE',
                isActive: _showCloud,
                onTap: () => setState(() => _showCloud = true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? SFColors.borderSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(SFRadius.small - 2),
        ),
        child: Center(
          child: Text(
            label,
            style: SFTypography.terminal.copyWith(
              fontSize: 10,
              color: isActive ? SFColors.textMain : SFColors.textMuted,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndStore() async {
    if (_uploading) return;
    final result = await FilePicker.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file  = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showSnack('COULD NOT READ FILE BYTES', isError: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(documentProvider.notifier).addDocument(
        name:       file.name,
        plainBytes: Uint8List.fromList(bytes),
      );
      _showSnack('DOCUMENT ENCRYPTED & STORED');
    } catch (e) {
      _showSnack('ENCRYPTION FAILED: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: SFColors.bgCard,
      content: Text(msg,
          style: SFTypography.metadata.copyWith(
              color: isError ? SFColors.danger : SFColors.textMuted)),
    ));
  }

  Future<void> _openDocument(VaultDocument doc) async {
    Uint8List bytes;
    try {
      bytes = await ref.read(documentProvider.notifier).openDocument(doc.id);
    } catch (e) {
      _showSnack('DECRYPTION FAILED: $e', isError: true);
      return;
    }
    if (!mounted) return;

    if (doc.isPdf) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _PdfViewerScreen(name: doc.name, bytes: bytes),
      ));
    } else if (doc.isImage) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _ImageViewerScreen(name: doc.name, bytes: bytes),
      ));
    } else if (doc.isText) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _TextViewerScreen(name: doc.name, bytes: bytes),
      ));
    } else {
      _showSnack('PREVIEW NOT SUPPORTED FOR THIS FORMAT');
    }
  }

  Future<void> _confirmDelete(VaultDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(name: doc.name),
    );
    if (ok == true) {
      await ref.read(documentProvider.notifier).deleteDocument(doc.id);
      _showSnack('DOCUMENT DESTROYED');
    }
  }

  Future<void> _syncDocumentToCloud(VaultDocument doc) async {
    final cloud = ref.read(cloudServiceProvider).valueOrNull;
    if (cloud == null) {
      _showSnack('CLOUD NOT CONFIGURED — ADD AWS CREDENTIALS IN SETTINGS', isError: true);
      return;
    }

    final crypto = ref.read(cryptoServiceProvider);
    if (!crypto.isUnlocked) {
      _showSnack('VAULT LOCKED — BIOMETRIC AUTH REQUIRED', isError: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final plainBytes = await ref.read(documentProvider.notifier).openDocument(doc.id);
      final encBlob = crypto.encryptToBlob(plainBytes);
      await cloud.uploadVaultFile(encBlob, 'docs/${doc.id}.enc');
      
      // Update local db and provider state
      await ref.read(databaseServiceProvider).markSynced(doc.id);
      await ref.read(documentProvider.notifier).load(); // reload local state
      
      // Refresh S3 grid list
      ref.invalidate(vaultFilesProvider);

      _showSnack('SYNCED TO CLOUD: ${doc.name}');
    } catch (e) {
      _showSnack('CLOUD SYNC FAILED: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentProvider);
    final filesAsync = ref.watch(vaultFilesProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: _uploading
            ? const SizedBox(
                width: 52, height: 52,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: SFColors.textMuted),
              )
            : GestureDetector(
                onTap: _showCloud ? _pickAndUpload : _pickAndStore,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: SFColors.textMain,
                    borderRadius: BorderRadius.circular(SFRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: SFColors.bgPrimary, size: 24),
                ),
              ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(SFSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DOCUMENT VAULT', style: SFTypography.h1),
                      const SizedBox(height: 4),
                      Text(
                        _showCloud
                            ? (filesAsync.valueOrNull != null
                                ? '${filesAsync.value!.length} FILE${filesAsync.value!.length == 1 ? '' : 'S'} · S3 CLOUD'
                                : 'CLOUD FILES · S3 CLOUD')
                            : '${docs.length} DOCUMENT${docs.length == 1 ? '' : 'S'}',
                        style: SFTypography.metadata.copyWith(color: SFColors.textFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SFSpacing.xs),

                _buildTabSelector(),

                const SizedBox(height: SFSpacing.lg),

                // Document list / Cloud grid with Pull-to-Refresh
                Expanded(
                  child: RefreshIndicator(
                    color: SFColors.textMain,
                    backgroundColor: SFColors.bgCard,
                    strokeWidth: 1.5,
                    onRefresh: () async {
                      ref.invalidate(vaultFilesProvider);
                      await ref.read(documentProvider.notifier).load();
                      await ref.read(vaultFilesProvider.future).catchError((_) => <VaultFile>[]);
                    },
                    child: _showCloud
                        ? filesAsync.when(
                            data: (files) => files.isEmpty
                                ? CloudEmptyState(onUpload: _pickAndUpload)
                                : CloudFileGrid(files: files),
                            loading: () => const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 1, color: SFColors.textMuted),
                            ),
                            error: (e, _) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(SFSpacing.xl),
                                  child: Text('ERROR: $e',
                                      style: SFTypography.metadata
                                          .copyWith(color: SFColors.danger)),
                                ),
                              ],
                            ),
                          )
                        : (docs.isEmpty
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.folder_open_outlined,
                                          size: 36, color: SFColors.textFaint),
                                      const SizedBox(height: SFSpacing.sm),
                                      Text('NO DOCUMENTS STORED',
                                          style: SFTypography.metadata
                                              .copyWith(color: SFColors.textFaint)),
                                      const SizedBox(height: SFSpacing.xl),
                                      GestureDetector(
                                        onTap: _pickAndStore,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: SFColors.borderMedium),
                                            borderRadius: BorderRadius.circular(
                                                SFRadius.small),
                                          ),
                                          child: const TacticalLabel(
                                              'TAP + TO ADD FIRST DOCUMENT',
                                              color: SFColors.textMuted),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: SFSpacing.base,
                                    vertical: SFSpacing.xs),
                                itemCount: docs.length,
                                separatorBuilder: (_, __) => const Divider(
                                    color: SFColors.borderSoft, height: 1),
                                itemBuilder: (_, i) => _DocumentTile(
                                  doc: docs[i],
                                  onOpen: () => _openDocument(docs[i]),
                                  onSync: () => _syncDocumentToCloud(docs[i]),
                                  onDelete: () => _confirmDelete(docs[i]),
                                ),
                              )),
                  ),
                ),
                const SizedBox(height: 110), // Padding below navigation pill
              ],
            ),
            if (_uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withAlpha(150),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: SFColors.textMain,
                        ),
                        const SizedBox(height: SFSpacing.md),
                        Text(
                          _showCloud
                              ? 'ENCRYPTING & UPLOADING TO S3...'
                              : 'ENCRYPTING & STORING SECURELY...',
                          style: SFTypography.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Document list tile ───────────────────────────────────────────────────────

class _DocumentTile extends StatelessWidget {
  final VaultDocument doc;
  final VoidCallback onOpen;
  final VoidCallback onSync;
  final VoidCallback onDelete;

  const _DocumentTile({
    required this.doc,
    required this.onOpen,
    required this.onSync,
    required this.onDelete,
  });

  IconData get _icon {
    if (doc.isPdf)   return Icons.picture_as_pdf_outlined;
    if (doc.isImage) return Icons.image_outlined;
    if (doc.isText)  return Icons.text_snippet_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SFSpacing.sm),
        child: Row(
          children: [
            // File type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SFColors.bgElevated,
                borderRadius: BorderRadius.circular(SFRadius.small),
              ),
              child: Icon(_icon, size: 20, color: SFColors.textMuted),
            ),
            const SizedBox(width: SFSpacing.sm),

            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    style: SFTypography.body.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        doc.sizeLabel,
                        style: SFTypography.metadata
                            .copyWith(color: SFColors.textFaint, fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: doc.isSynced
                              ? SFColors.successMuted
                              : SFColors.bgElevated,
                          borderRadius: BorderRadius.circular(SFRadius.pill),
                          border: Border.all(
                            color: doc.isSynced
                                ? SFColors.success.withAlpha(60)
                                : SFColors.borderSoft,
                          ),
                        ),
                        child: Text(
                          doc.isSynced ? 'SYNCED' : 'LOCAL',
                          style: SFTypography.metadata.copyWith(
                            color: doc.isSynced
                                ? SFColors.success
                                : SFColors.textFaint,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!doc.isSynced)
                  GestureDetector(
                    onTap: onSync,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.cloud_upload_outlined,
                          size: 16, color: SFColors.textFaint),
                    ),
                  ),
                GestureDetector(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: SFColors.textFaint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Confirm delete dialog ────────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  final String name;
  const _ConfirmDeleteDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SFColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFRadius.card),
        side: const BorderSide(color: SFColors.borderDanger),
      ),
      title: Text('DESTROY DOCUMENT', style: SFTypography.cardTitle),
      content: Text(
        '"$name" will be permanently deleted\nfrom local storage and S3 cloud.',
        style: SFTypography.bodyMuted,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('CANCEL',
              style: SFTypography.metadata
                  .copyWith(color: SFColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('DESTROY',
              style: SFTypography.metadata
                  .copyWith(color: SFColors.danger)),
        ),
      ],
    );
  }
}

// ─── In-app PDF Viewer ────────────────────────────────────────────────────────

class _PdfViewerScreen extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  const _PdfViewerScreen({required this.name, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: SFColors.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SFColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(name,
            style: SFTypography.body.copyWith(fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
      body: SfPdfViewer.memory(bytes),
    );
  }
}

// ─── In-app Image Viewer ──────────────────────────────────────────────────────

class _ImageViewerScreen extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  const _ImageViewerScreen({required this.name, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: SFColors.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SFColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(name,
            style: SFTypography.body.copyWith(fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ─── In-app Text Viewer ───────────────────────────────────────────────────────

class _TextViewerScreen extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  const _TextViewerScreen({required this.name, required this.bytes});

  @override
  Widget build(BuildContext context) {
    final text = String.fromCharCodes(bytes);
    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: SFColors.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SFColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(name,
            style: SFTypography.body.copyWith(fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SFSpacing.base),
        child: SelectableText(
          text,
          style: SFTypography.body.copyWith(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
