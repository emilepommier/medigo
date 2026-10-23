import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/utils/drug_text.dart';
import 'package:medigo/services/add_to_pharmacy_flow.dart';
import 'package:medigo/theme.dart';
import 'package:medigo/components/identity_header.dart';
import 'package:medigo/components/box_photo_placeholder.dart';
import 'package:medigo/components/month_year_picker_sheet.dart';
import 'package:medigo/components/box_entry_tile.dart';
import 'package:medigo/services/drug_photo_service.dart';
import 'package:medigo/services/lab_logo_service.dart';
import 'package:medigo/services/roles.dart';
import 'package:medigo/components/lab_logo_crop_sheet.dart';
import 'package:medigo/services/notification_service.dart';
import 'package:medigo/components/background_removal_preview.dart';
import 'package:medigo/components/box_photo_crop_sheet.dart';
import 'package:medigo/services/photo_filter_service.dart';

class PresentationDetailScreen extends StatefulWidget {
  final String cip13;
  const PresentationDetailScreen({super.key, required this.cip13});

  @override
  State<PresentationDetailScreen> createState() =>
      _PresentationDetailScreenState();
}

class _PresentationDetailScreenState extends State<PresentationDetailScreen> {
  Map<String, dynamic>? _presentation;
  List<InventoryEntry> _entries = [];
  bool _loading = true;
  bool _adding = false;
  Uint8List? _boxPhotoBytes;
  Uint8List? _labLogoBytes;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    try {
      final admin = await RolesService.isAdmin();
      if (mounted) setState(() => _isAdmin = admin);
    } catch (e) {
      debugPrint('PresentationDetail: _checkAdmin failed: $e');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseConfig.client
          .from('presentations')
          .select(
              'cip13,cip7,libelle,prix_euro,cis,drugs(denomination,forme,titulaires)')
          .eq('cip13', widget.cip13)
          .maybeSingle();
      final entries = await PharmacieStore.loadEntriesForDisplay(widget.cip13);
      setState(() {
        _presentation = data;
        _entries = entries;
      });
      try {
        final bytes = await DrugPhotoService.getCoverBytes(widget.cip13);
        if (mounted) setState(() => _boxPhotoBytes = bytes);
      } catch (e) {
        debugPrint('PresentationDetail: resolve cover bytes failed: $e');
      }
      // Resolve lab logo (global, keyed by titulaire)
      try {
        final drugs = (data)?['drugs'] as Map<String, dynamic>?;
        String manufacturer = '';
        if (drugs != null && drugs['titulaires'] is List && (drugs['titulaires'] as List).isNotEmpty) {
          manufacturer = ((drugs['titulaires'] as List).first ?? '').toString();
        }
        if (manufacturer.trim().isNotEmpty) {
          final logo = await LabLogoService.getLogoBytes(manufacturer);
          if (mounted) setState(() => _labLogoBytes = logo);
        } else {
          if (mounted) setState(() => _labLogoBytes = null);
        }
      } catch (e) {
        debugPrint('PresentationDetail: resolve lab logo failed: $e');
      }
    } catch (e) {
      debugPrint('Presentation detail load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBox() async {
    setState(() => _adding = true);
    await AddToPharmacyFlow.add(context: context, cip13: widget.cip13);
    await _load();
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _showPhotoActions() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      if (SupabaseConfig.auth.currentUser == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour importer une photo.')));
                        return;
                      }
                      final picker = ImagePicker();
                      final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
                      if (x != null) {
                        final bytes = await x.readAsBytes();
                        final processedBytes = await BackgroundRemovalPreview.show(context, bytes);
                        if (processedBytes != null) {
                          // Step 2: auto-apply uniform photo filter (Brannan)
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _BlockingLoader(message: 'Application du filtre...'),
                          );
                          Uint8List filtered;
                          try {
                            filtered = await PhotoFilterService.applyBrannan(processedBytes);
                          } finally {
                            if (context.mounted) Navigator.of(context).pop(); // close loader
                          }
                          // Step 3: crop to 16:9 to match BoxPhotoPlaceholder
                          final cropped = await BoxPhotoCropSheet.show(context, filtered);
                          if (cropped == null) return;
                          // Step 4: upload with loader
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _BlockingLoader(message: 'Téléversement...'),
                          );
                          String? path;
                          try {
                            path = await DrugPhotoService.uploadCover(cipKey: widget.cip13, bytes: cropped, contentType: 'image/png');
                          } finally {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                          if (path != null) {
                            await PharmacieStore.setPhotoForCip(widget.cip13, path);
                            if (mounted) setState(() { _boxPhotoBytes = cropped; });
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('Camera import failed: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'import.')));
                      }
                    }
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Prendre une photo'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      if (SupabaseConfig.auth.currentUser == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour importer une photo.')));
                        return;
                      }
                      final picker = ImagePicker();
                      final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
                      if (x != null) {
                        final bytes = await x.readAsBytes();
                        final processedBytes = await BackgroundRemovalPreview.show(context, bytes);
                        if (processedBytes != null) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _BlockingLoader(message: 'Application du filtre...'),
                          );
                          Uint8List filtered;
                          try {
                            filtered = await PhotoFilterService.applyBrannan(processedBytes);
                          } finally {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                          final cropped = await BoxPhotoCropSheet.show(context, filtered);
                          if (cropped == null) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _BlockingLoader(message: 'Téléversement...'),
                          );
                          String? path;
                          try {
                            path = await DrugPhotoService.uploadCover(cipKey: widget.cip13, bytes: cropped, contentType: 'image/png');
                          } finally {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                          if (path != null) {
                            await PharmacieStore.setPhotoForCip(widget.cip13, path);
                            if (mounted) setState(() { _boxPhotoBytes = cropped; });
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('Gallery import failed: $e');
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choisir depuis la galerie'),
                ),
                if (_boxPhotoBytes != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await DrugPhotoService.deleteCoverByCipKey(widget.cip13);
                        await PharmacieStore.clearPhotoForCip(widget.cip13);
                        if (mounted) setState(() => _boxPhotoBytes = null);
                      } catch (e) {
                        debugPrint('Delete photo failed: $e');
                      } finally {
                        if (context.mounted) Navigator.of(ctx).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer la photo'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLabLogoActions() async {
    if (!_isAdmin) return;
    // Derive current titulaire name
    String manufacturer = '';
    final drugs = _presentation?['drugs'] as Map<String, dynamic>?;
    if (drugs != null && drugs['titulaires'] is List && (drugs['titulaires'] as List).isNotEmpty) {
      manufacturer = ((drugs['titulaires'] as List).first ?? '').toString();
    }
    if (manufacturer.trim().isEmpty) return;
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final picker = ImagePicker();
                      // Pick original; we'll crop to square and resize to small PNG
                      final x = await picker.pickImage(source: ImageSource.gallery);
                      if (x != null) {
                        final bytes = await x.readAsBytes();
                        final cropped = await LabLogoCropSheet.show(context, bytes);
                        if (cropped != null) {
                          final path = await LabLogoService.uploadLogo(titulaire: manufacturer, bytes: cropped, contentType: 'image/png');
                          if (path != null && mounted) setState(() => _labLogoBytes = cropped);
                        }
                      }
                    } catch (e) {
                      debugPrint('Gallery pick (logo) failed: $e');
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir la galerie.')));
                    } finally {
                      if (context.mounted) Navigator.of(ctx).pop();
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Importer une image'),
                ),
                if (_labLogoBytes != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      LabLogoService.deleteLogo(manufacturer).then((_) {
                        if (mounted) setState(() => _labLogoBytes = null);
                      }).whenComplete(() {
                        if (context.mounted) Navigator.of(ctx).pop();
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer le logo'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEntry(InventoryEntry entry) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_forever, color: scheme.onErrorContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Supprimer cette boîte ?', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          "Cette action retirera définitivement cette boîte de votre pharmacie.",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(scheme.error)),
                      onPressed: () => context.pop(true),
                      child: Text('Supprimer', style: TextStyle(color: scheme.onError)),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    if (confirm == true) {
      // Ignore synthetic placeholders
      if (entry.id.startsWith('placeholder-')) {
        await PharmacieStore.decrementOrRemove(entry.cip13, by: 1);
      } else {
        await PharmacieStore.removeEntry(entry.cip13, entry.id);
      }
      await _load();
    }
  }

  Future<void> _editExpiry(InventoryEntry entry) async {
    final picked = await MonthYearPickerSheet.show(context, initialDate: entry.expiresAt);
    if (picked != null) {
      final old = entry.expiresAt;
      await PharmacieStore.updateEntry(entry.id, entry.cip13, expiresAt: picked);
      // Reschedule notifications for this drug-month
      try {
        if (old != null) await NotificationService.cancelFor(cip13: entry.cip13, expiresAt: old);
        await NotificationService.scheduleMonthNotification(cip13: entry.cip13, expiresAt: picked);
        if (NotificationService.isSameMonth(DateTime.now(), picked)) {
          await NotificationService.notifyIfCurrentMonth(cip13: entry.cip13, expiresAt: picked);
        }
      } catch (e) { debugPrint('Reschedule after edit failed: $e'); }
      await _load();
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final data = _presentation;
    final drugs =
        data != null ? (data['drugs'] as Map<String, dynamic>?) : null;
    final rawDenom =
        drugs != null ? (drugs['denomination'] as String? ?? '') : '';
    final forme = drugs != null ? (drugs['forme'] as String? ?? '') : '';
    final title = DrugTextUtils.sanitizeDenomination(rawDenom, forme);
    String manufacturer = '';
    if (drugs != null &&
        drugs['titulaires'] is List &&
        (drugs['titulaires'] as List).isNotEmpty) {
      manufacturer = ((drugs['titulaires'] as List).first ?? '').toString();
    }
    final libelle = (data?['libelle'] as String? ?? '').trim();
    final prix = data?['prix_euro'];

    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // BOX PHOTO PLACEHOLDER / PREVIEW
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: BoxPhotoPlaceholder(imageBytes: _boxPhotoBytes, imageUrl: null, onTap: _showPhotoActions),
                  ),
                ),
                // HERO IDENTITY CARD
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: IdentityHeader(
                      title: title.isNotEmpty ? title : (libelle.isNotEmpty ? libelle : 'Médicament'),
                      forme: forme,
                      manufacturer: manufacturer,
                      cip13: widget.cip13,
                      price: (prix is num) ? prix.toDouble() : null,
                      avatarImageBytes: _labLogoBytes,
                       onAvatarTap: (_isAdmin && manufacturer.trim().isNotEmpty) ? _showLabLogoActions : null,
                    ),
                  ),
                ),
                // Libellé block
                if (libelle.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(libelle, style: t.bodyMedium, softWrap: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Removed section header per request
                // Boxes list
                if (_entries.isNotEmpty)
                  SliverList.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final e = _entries[index];
                      return BoxEntryTile(
                        index: index,
                        entry: e,
                        onEditExpiry: () => _editExpiry(e),
                        onDelete: () => _deleteEntry(e),
                      );
                    },
                  ),
                if (_entries.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Aucune boîte enregistrée pour cette présentation.',
                                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _addBox,
                                icon: const Icon(Icons.add),
                                label: const Text('Ajouter'),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _adding ? null : _addBox,
        tooltip: 'Ajouter une boîte',
        child: _adding ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
      ),
    );
  }
}

class _BlockingLoader extends StatelessWidget {
  final String message;
  const _BlockingLoader({required this.message});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
      ),
    );
  }
}
// Components moved to lib/components/*
