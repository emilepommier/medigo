import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/components/identity_header.dart';
import 'package:medigo/components/box_photo_placeholder.dart';
import 'package:medigo/components/box_entry_tile.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medigo/components/month_year_picker_sheet.dart';
import 'package:medigo/theme.dart';
import 'package:medigo/services/drug_photo_service.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/lab_logo_service.dart';
import 'package:medigo/services/roles.dart';
import 'package:medigo/components/lab_logo_crop_sheet.dart';
import 'package:medigo/components/background_removal_preview.dart';
import 'package:medigo/components/box_photo_crop_sheet.dart';
import 'package:medigo/services/photo_filter_service.dart';

class CustomItemDetailScreen extends StatefulWidget {
  final String customKey;
  const CustomItemDetailScreen({super.key, required this.customKey});

  @override
  State<CustomItemDetailScreen> createState() => _CustomItemDetailScreenState();
}

class _CustomItemDetailScreenState extends State<CustomItemDetailScreen> {
  Map<String, dynamic>? _meta;
  List<InventoryEntry> _entries = [];
  bool _loading = true;
  bool _savingMeta = false;
  Uint8List? _boxPhotoBytes;
  Uint8List? _labLogoBytes;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkAdmin();
  }

  Future<void> _editMeta() async {
    if (_meta == null) return;
    final nameCtrl = TextEditingController(text: _meta?['name']?.toString() ?? '');
    final labCtrl = TextEditingController(text: _meta?['laboratory']?.toString() ?? '');
    final formeCtrl = TextEditingController(text: _meta?['forme']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit),
                    const SizedBox(width: 8),
                    Text('Modifier', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.medication_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: labCtrl,
                  decoration: const InputDecoration(labelText: 'Laboratoire', prefixIcon: Icon(Icons.factory_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: formeCtrl,
                  decoration: const InputDecoration(labelText: 'Forme', prefixIcon: Icon(Icons.category_outlined)),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        if (formKey.currentState!.validate()) Navigator.of(context).pop(true);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Enregistrer'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
    if (result == true) {
      setState(() => _savingMeta = true);
      try {
        final ok = await PharmacieStore.updateCustomMeta(
          customKey: widget.customKey,
          name: nameCtrl.text.trim(),
          laboratory: labCtrl.text.trim(),
          forme: formeCtrl.text.trim(),
        );
        if (!mounted) return;
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modifications enregistrées.')));
          await _load();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Échec de la mise à jour.')));
        }
      } catch (e) {
        debugPrint('Edit meta failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la mise à jour.')));
        }
      } finally {
        if (mounted) setState(() => _savingMeta = false);
      }
    }
  }

  Future<void> _load() async {
    try {
      final meta = await PharmacieStore.loadCustomMeta(widget.customKey);
      final entries = await PharmacieStore.loadEntriesForDisplay(widget.customKey);
      setState(() {
        _meta = meta;
        _entries = entries;
        _loading = false;
      });
      try {
        final path = meta?['photo_url'] as String?;
        if (path != null && path.isNotEmpty) {
          final bytes = await SupabaseConfig.client.storage.from(DrugPhotoService.bucket).download(path);
          if (mounted) setState(() => _boxPhotoBytes = bytes);
        } else {
          if (mounted) setState(() => _boxPhotoBytes = null);
        }
      } catch (e) {
        debugPrint('Custom detail resolve bytes failed: $e');
      }
      // Resolve global lab logo by titulaire/laboratory if provided
      try {
        final lab = meta?['laboratory']?.toString() ?? '';
        if (lab.trim().isNotEmpty) {
          final logo = await LabLogoService.getLogoBytes(lab);
          if (mounted) setState(() => _labLogoBytes = logo);
        } else {
          if (mounted) setState(() => _labLogoBytes = null);
        }
      } catch (e) {
        debugPrint('Custom detail resolve lab logo failed: $e');
      }
    } catch (e) {
      debugPrint('CustomItemDetailScreen load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkAdmin() async {
    try {
      final admin = await RolesService.isAdmin();
      if (mounted) setState(() => _isAdmin = admin);
    } catch (e) {
      debugPrint('CustomDetail: _checkAdmin failed: $e');
    }
  }

  Future<void> _addOne() async {
    final picked = await MonthYearPickerSheet.show(context);
    if (picked == null) return;
    await PharmacieStore.addOrIncrement(widget.customKey, expiresAt: picked);
    await _load();
  }

  Future<void> _removeEntry(InventoryEntry entry) async {
    if (_entries.isEmpty) return;
    // If this is a real entry id, remove that specific one; otherwise decrement
    if (entry.id.startsWith('placeholder-')) {
      await PharmacieStore.decrementOrRemove(widget.customKey, by: 1);
    } else {
      await PharmacieStore.removeEntry(widget.customKey, entry.id);
    }
    await _load();
  }

  Future<void> _editExpiry(InventoryEntry entry) async {
    final picked = await MonthYearPickerSheet.show(context, initialDate: entry.expiresAt);
    if (picked != null) {
      // Ignore synthetic placeholders
      if (!entry.id.startsWith('placeholder-')) {
        await PharmacieStore.updateEntry(entry.id, widget.customKey, expiresAt: picked);
      }
      await _load();
    }
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
                            path = await DrugPhotoService.uploadCover(cipKey: widget.customKey, bytes: cropped, contentType: 'image/png');
                          } finally {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                          if (path != null) {
                            await PharmacieStore.updateCustomPhoto(customKey: widget.customKey, photoPath: path);
                            if (mounted) setState(() { _boxPhotoBytes = cropped; });
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('Camera import failed: $e');
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
                            path = await DrugPhotoService.uploadCover(cipKey: widget.customKey, bytes: cropped, contentType: 'image/png');
                          } finally {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                          if (path != null) {
                            await PharmacieStore.updateCustomPhoto(customKey: widget.customKey, photoPath: path);
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
                        await DrugPhotoService.deleteCoverByCipKey(widget.customKey);
                        await PharmacieStore.updateCustomPhoto(customKey: widget.customKey, photoPath: null);
                        if (mounted) setState(() => _boxPhotoBytes = null);
                      } catch (e) {
                        debugPrint('Delete cover failed: $e');
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
    final lab = _meta?['laboratory']?.toString() ?? '';
    if (lab.trim().isEmpty) return;
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
                          final path = await LabLogoService.uploadLogo(titulaire: lab, bytes: cropped, contentType: 'image/png');
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
                      LabLogoService.deleteLogo(lab).then((_) {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final name = _meta?['name']?.toString() ?? 'Médicament';
    final lab = _meta?['laboratory']?.toString();
    final forme = _meta?['forme']?.toString();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          // Top gradient box placeholder to match presentation detail view
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: BoxPhotoPlaceholder(imageBytes: _boxPhotoBytes, imageUrl: null, onTap: _showPhotoActions),
            ),
          ),
          // Identity header (no CIP/price for manual drugs)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: IdentityHeader(
                title: name,
                forme: (forme ?? '').trim().isEmpty ? null : forme,
                manufacturer: (lab ?? '').trim().isEmpty ? null : lab,
                cip13: null,
                price: null,
                avatarImageBytes: _labLogoBytes,
                onAvatarTap: (_isAdmin && (lab ?? '').trim().isNotEmpty) ? _showLabLogoActions : null,
                trailing: IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _savingMeta ? null : _editMeta,
                ),
              ),
            ),
          ),
          // Removed section header per request
          // Boxes list (shared tile)
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
                  onDelete: () => _removeEntry(e),
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
                    child: Row(children: [
                      Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Aucune boîte enregistrée pour cet article.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(onPressed: _addOne, icon: const Icon(Icons.add), label: const Text('Ajouter')),
                    ]),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addOne,
        tooltip: 'Ajouter une boîte',
        child: const Icon(Icons.add),
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
