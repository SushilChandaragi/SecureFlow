/// Cloud Vault Screen — masonry grid of encrypted assets (§2)
library;

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
import '../widgets/sf_badge.dart';
import 'document_viewer_screen.dart';

class CloudVaultScreen extends ConsumerWidget {
  const CloudVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  child: filesAsync.when(
                    data: (files) => files.isEmpty
                        ? _EmptyState()
                        : _FileGrid(files: files),
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 1, color: SFColors.textMuted),
                    ),
                    error: (e, _) => Center(
                      child: Text('ERROR: $e',
                          style: SFTypography.metadata.copyWith(color: SFColors.danger)),
                    ),
                  ),
                ),
              ],
            ),
            // Persistent FAB (§2 Cloud Vault)
            Positioned(
              bottom: 90,
              right: SFSpacing.base,
              child: _UploadFab(ref: ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileGrid extends StatelessWidget {
  final List<VaultFile> files;
  const _FileGrid({required this.files});

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
        itemBuilder: (_, i) => _FileCard(file: files[i]),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final VaultFile file;
  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      onTap: () {
        // Navigate to document viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DocumentViewerRoute(file: file),
          ),
        );
      },
      padding: const EdgeInsets.all(SFSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File icon + classification
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_fileIcon(file.name), size: 20, color: SFColors.textMuted),
              SFBadge(file.classification),
            ],
          ),
          const SizedBox(height: SFSpacing.sm),
          Text(
            file.displayName,
            style: SFTypography.body.copyWith(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          TacticalLabel(file.formattedSize, color: SFColors.textFaint),
          if (file.lastModified != null) ...[
            const SizedBox(height: 2),
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

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 40, color: SFColors.textFaint),
          SizedBox(height: SFSpacing.sm),
          TacticalLabel(SFCopy.vaultEmpty, color: SFColors.textFaint),
        ],
      ),
    );
  }
}

class _UploadFab extends StatelessWidget {
  final WidgetRef ref;
  const _UploadFab({required this.ref});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showUploadDialog(context),
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
    );
  }

  void _showUploadDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(SFSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TacticalLabel(SFCopy.secureUpload, color: SFColors.textMuted),
            const SizedBox(height: SFSpacing.md),
            Text('SELECT A FILE TO ENCRYPT AND UPLOAD',
                style: SFTypography.bodyMuted),
            const SizedBox(height: SFSpacing.xl),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        ),
      ),
    );
  }
}

// Navigates to the document viewer
class _DocumentViewerRoute extends StatelessWidget {
  final VaultFile file;
  const _DocumentViewerRoute({required this.file});

  @override
  Widget build(BuildContext context) {
    return DocumentViewerScreen(file: file);
  }
}
