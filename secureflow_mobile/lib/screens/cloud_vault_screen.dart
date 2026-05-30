/// Cloud Vault Screen — masonry grid of encrypted assets + file upload (§2)
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/vault_file.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';
import 'document_viewer_screen.dart';

class CloudVaultScreen extends ConsumerStatefulWidget {
  const CloudVaultScreen({super.key});

  @override
  ConsumerState<CloudVaultScreen> createState() => _CloudVaultScreenState();
}

class _CloudVaultScreenState extends ConsumerState<CloudVaultScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    // Check cloud configured
    final cloud = ref.read(cloudServiceProvider).valueOrNull;
    if (cloud == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SFColors.bgCard,
          content: Text(
            'CLOUD NOT CONFIGURED — ADD AWS CREDENTIALS IN SETTINGS',
            style: SFTypography.metadata.copyWith(color: SFColors.danger),
          ),
        ),
      );
      return;
    }

    // Pick file (reads bytes into RAM, no disk copy)
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SFColors.bgCard,
          content: Text('COULD NOT READ FILE', style: SFTypography.metadata),
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      // Encrypt then upload
      final crypto = ref.read(cryptoServiceProvider);
      final encrypted = crypto.isUnlocked
          ? crypto.encryptToBlob(bytes)
          : bytes; // No vault key — upload raw (user should see warning)

      final uploadName = file.name.endsWith('.enc') ? file.name : '${file.name}.enc';
      await cloud.uploadVaultFile(encrypted, uploadName);

      // Refresh the file list
      ref.invalidate(vaultFilesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SFColors.bgCard,
          content: Text(
            'UPLOADED: $uploadName',
            style: SFTypography.metadata.copyWith(color: SFColors.success),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SFColors.bgCard,
          content: Text(
            'UPLOAD FAILED: $e',
            style: SFTypography.metadata.copyWith(color: SFColors.danger),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(vaultFilesProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(SFSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TacticalLabel('GHOST WAREHOUSE', color: SFColors.textMuted),
                      const SizedBox(height: 6),
                      Text('CLOUD VAULT', style: SFTypography.h1),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: SFColors.textMain,
                    backgroundColor: SFColors.bgCard,
                    strokeWidth: 1.5,
                    onRefresh: () async {
                      ref.invalidate(vaultFilesProvider);
                      // Wait for the new future to settle before releasing indicator.
                      // The catchError must return List<VaultFile> to satisfy the type system.
                      await ref
                          .read(vaultFilesProvider.future)
                          .catchError((_) => <VaultFile>[]);
                    },
                    child: filesAsync.when(
                      data: (files) => files.isEmpty
                          ? CloudEmptyState(onUpload: _pickAndUpload)
                          : CloudFileGrid(files: files),
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 1, color: SFColors.textMuted),
                      ),
                      error: (e, _) => ListView(
                        // ListView is needed so RefreshIndicator has a scrollable
                        // child to attach its overscroll gesture to.
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(SFSpacing.xl),
                            child: Text('ERROR: $e',
                                style: SFTypography.metadata
                                    .copyWith(color: SFColors.danger)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Upload progress overlay
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
                        Text('ENCRYPTING & UPLOADING...',
                            style: SFTypography.metadata),
                      ],
                    ),
                  ),
                ),
              ),

            // FAB
            Positioned(
              bottom: 90,
              right: SFSpacing.base,
              child: _uploading
                  ? const SizedBox.shrink()
                  : _UploadFab(onTap: _pickAndUpload),
            ),
          ],
        ),
      ),
    );
  }
}

class CloudFileGrid extends StatelessWidget {
  final List<VaultFile> files;
  const CloudFileGrid({super.key, required this.files});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SFSpacing.base, 0, SFSpacing.base, SFSpacing.xl),
      child: MasonryGridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: SFSpacing.base,
        crossAxisSpacing: SFSpacing.base,
        itemCount: files.length,
        itemBuilder: (_, i) => CloudFileCard(file: files[i]),
      ),
    );
  }
}

class CloudFileCard extends ConsumerWidget {
  final VaultFile file;
  const CloudFileCard({super.key, required this.file});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SFColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.card),
          side: const BorderSide(color: SFColors.borderDanger),
        ),
        title: Text('DESTROY CLOUD FILE', style: SFTypography.cardTitle),
        content: Text(
          '"${file.displayName}" will be permanently deleted\nfrom S3 cloud vault.',
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
      ),
    );

    if (confirm == true) {
      final cloud = ref.read(cloudServiceProvider).valueOrNull;
      if (cloud != null) {
        try {
          await cloud.deleteVaultFile(file.name);
          ref.invalidate(vaultFilesProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: SFColors.bgCard,
                content: Text(
                  'DELETED FROM CLOUD: ${file.displayName}',
                  style: SFTypography.metadata.copyWith(color: SFColors.success),
                ),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: SFColors.bgCard,
                content: Text(
                  'DELETE FAILED: $e',
                  style: SFTypography.metadata.copyWith(color: SFColors.danger),
                ),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BentoCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DocumentViewerScreen(file: file),
          ),
        );
      },
      padding: const EdgeInsets.all(SFSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_fileIcon(file.name), size: 20, color: SFColors.textMuted),
              GestureDetector(
                onTap: () => _confirmDelete(context, ref),
                child: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: SFColors.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: SFSpacing.sm),
          Text(
            file.displayName,
            style: SFTypography.body.copyWith(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (file.sizeBytes > 0) ...[
            const SizedBox(height: 4),
            TacticalLabel(file.formattedSize, color: SFColors.textFaint),
          ],
          if (file.lastModified != null) ...[
            const SizedBox(height: 4),
            TacticalLabel(
              _formatDate(file.lastModified!),
              color: SFColors.textFaint,
            ),
          ],
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('pass') || n.contains('cred')) return Icons.key_outlined;
    if (n.contains('auth') || n.contains('totp')) return Icons.shield_outlined;
    if (n.contains('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.contains('.txt') || n.contains('.md')) return Icons.article_outlined;
    return Icons.lock_outline;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class CloudEmptyState extends StatelessWidget {
  final VoidCallback onUpload;
  const CloudEmptyState({super.key, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 40, color: SFColors.textFaint),
          const SizedBox(height: SFSpacing.sm),
          const TacticalLabel(SFCopy.vaultEmpty, color: SFColors.textFaint),
          const SizedBox(height: SFSpacing.xl),
          GestureDetector(
            onTap: onUpload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: SFColors.borderMedium),
                borderRadius: BorderRadius.circular(SFRadius.small),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upload_outlined, size: 14, color: SFColors.textMuted),
                  const SizedBox(width: 8),
                  Text(SFCopy.secureUpload,
                      style: SFTypography.metadata.copyWith(color: SFColors.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadFab extends StatelessWidget {
  final VoidCallback onTap;
  const _UploadFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
        child: const Icon(Icons.upload_outlined, color: SFColors.bgPrimary, size: 22),
      ),
    );
  }
}
