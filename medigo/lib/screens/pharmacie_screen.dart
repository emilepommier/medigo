import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/screens/scan_cip_page.dart';
import 'package:medigo/services/cip_parser.dart';
import 'package:medigo/utils/drug_text.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/theme.dart';
import 'package:medigo/services/add_to_pharmacy_flow.dart';
import 'package:medigo/services/drug_photo_service.dart';
import 'package:medigo/components/box_image_fullscreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medigo/services/family_service.dart';

class PharmacieScreen extends StatefulWidget {
  const PharmacieScreen({super.key});

  @override
  State<PharmacieScreen> createState() => PharmacieScreenState();
}

class PharmacieScreenState extends State<PharmacieScreen> {
  List<InventoryItem> _items = [];
  bool _loading = true;
  RealtimeChannel? _entriesChannel;
  StreamSubscription<void>? _storeChangesSub;
  bool _listMode = false; // false: cards (default), true: list

  // New: in-memory caches for presentation metadata and entries futures per cip13
  final Map<String, Future<Map<String, dynamic>?>> _presentationFutureCache =
      {};
  final Map<String, Future<List<InventoryEntry>>> _entriesFutureCache = {};

  /// Public: force-refresh all data on the page (items, metadata & entries)
  Future<void> refreshAll() async {
    try {
      // Clear per-item future caches so FutureBuilders refetch
      _presentationFutureCache.clear();
      _entriesFutureCache.clear();
      // Reload aggregate items
      final fresh = await PharmacieStore.load();
      _items = fresh;
    } catch (e) {
      debugPrint('PharmacieScreen.refreshAll failed: $e');
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
    _storeChangesSub = PharmacieStore.changes.listen((_) => _reloadAndSet());
    _loadViewPreference();
  }

  Future<void> _load() async {
    try {
      _items = await PharmacieStore.load();
    } catch (e) {
      debugPrint('Failed to load pharmacie items: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _reloadAndSet() async {
    try {
      _items = await PharmacieStore.load();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Reload pharmacie items failed: $e');
    }
  }

  Future<void> _loadViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('pharmacie_view_list') ?? false;
      if (mounted) setState(() => _listMode = v);
    } catch (e) {
      debugPrint('Failed to load pharmacie view preference: $e');
    }
  }

  Future<void> _saveViewPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pharmacie_view_list', value);
    } catch (e) {
      debugPrint('Failed to save pharmacie view preference: $e');
    }
  }

  Future<void> _subscribeRealtime() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;
    final familyId = await FamilyService.getCurrentFamilyId();
    if (familyId == null) return;
    try {
      _entriesChannel =
          SupabaseConfig.client.channel('pharmacy_item_entries_changes')
            ..onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'pharmacy_item_entries',
              callback: (payload) {
                try {
                  final fid = payload.newRecord['family_id']?.toString();
                  if (fid == familyId) _reloadAndSet();
                } catch (_) {}
              },
            )
            ..onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: 'pharmacy_item_entries',
              callback: (payload) {
                try {
                  final fid = payload.oldRecord['family_id']?.toString();
                  if (fid == familyId) _reloadAndSet();
                } catch (_) {}
              },
            )
            ..subscribe();
    } catch (e) {
      debugPrint('Realtime subscribe failed: $e');
    }
  }

  @override
  void dispose() {
    try {
      _storeChangesSub?.cancel();
    } catch (_) {}
    if (_entriesChannel != null) {
      try {
        SupabaseConfig.client.removeChannel(_entriesChannel!);
      } catch (_) {}
      _entriesChannel = null;
    }
    super.dispose();
  }

  // Unified add flow used elsewhere handles expiry; no local prompt method needed.

  /// Public method to trigger scan-and-add flow from outside (e.g., FAB menu)
  Future<void> scanAndAdd() async {
    final parsed = await Navigator.of(context).push<CipParseResult>(
        MaterialPageRoute(builder: (_) => const ScanCipPage()));
    if (parsed == null) return;
    String? cip13 = parsed.cip13;
    if (cip13 == null && parsed.cip7 != null) {
      try {
        final res = await SupabaseConfig.client
            .from('presentations')
            .select('cip13')
            .eq('cip7', parsed.cip7!)
            .limit(1);
        if (res.isNotEmpty) {
          cip13 = (res.first)['cip13'] as String?;
        }
      } catch (e) {
        debugPrint('Resolve CIP7->CIP13 failed: $e');
      }
    }
    if (cip13 != null) {
      await AddToPharmacyFlow.add(context: context, cip13: cip13);
      _items = await PharmacieStore.load();
      if (mounted) setState(() {});
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aucun CIP valide détecté.")));
      }
    }
  }



  // Cached presentation loader used by list/grid items
  Future<Map<String, dynamic>?> _loadPresentation(String cip13) {
    final cached = _presentationFutureCache[cip13];
    if (cached != null) return cached;
    final future = _fetchPresentation(cip13);
    _presentationFutureCache[cip13] = future;
    return future;
  }

  // Actual fetch logic (uncached)
  Future<Map<String, dynamic>?> _fetchPresentation(String cip13) async {
    // Custom manual item branch
    if (cip13.startsWith('custom:')) {
      try {
        final meta = await PharmacieStore.loadCustomMeta(cip13);
        if (meta == null) return null;
        final name = meta['name'] as String?;
        final forme = meta['forme'] as String?;
        return {
          'cip13': cip13,
          'libelle': name,
          'drugs': {
            'denomination': name,
            'forme': forme,
            'titulaires': meta['laboratory']
          }
        };
      } catch (e) {
        debugPrint('Failed to load custom item $cip13: $e');
        return null;
      }
    }
    try {
      final res = await SupabaseConfig.client
          .from('presentations')
          .select(
              'cip13,cip7,libelle,prix_euro,cis,drugs(denomination,forme,titulaires)')
          .eq('cip13', cip13)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('Failed to load presentation $cip13: $e');
      return null;
    }
  }

  // Cached entries loader; avoids per-item duplicate network calls during scroll
  Future<List<InventoryEntry>> _loadEntries(String cip13) {
    final cached = _entriesFutureCache[cip13];
    if (cached != null) return cached;
    final future = PharmacieStore.loadEntriesForDisplay(cip13);
    _entriesFutureCache[cip13] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // View toggle (Cards/List) persisted in SharedPreferences
          Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Cartes'),
                      icon: Icon(Icons.grid_view)),
                  ButtonSegment(
                      value: true,
                      label: Text('Liste'),
                      icon: Icon(Icons.view_list)),
                ],
                selected: {_listMode},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  final v = s.first;
                  setState(() => _listMode = v);
                  _saveViewPreference(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Votre pharmacie est vide.'))
                : (_listMode
                    ? ListView.separated(
                        padding: const EdgeInsets.only(bottom: 48),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _PharmacieDrugListItem(
                            item: item,
                            loadPresentation: _loadPresentation,
                            loadEntries: _loadEntries,
                            onOpen: () {
                              if (item.cip13.startsWith('custom:')) {
                                context.pushNamed('custom_detail',
                                    queryParameters: {'key': item.cip13});
                              } else {
                                context.pushNamed('presentation_detail',
                                    pathParameters: {'cip13': item.cip13});
                              }
                            },
                          );
                        },
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          int crossAxisCount = 3;
                          if (w >= 1200) {
                            crossAxisCount = 5;
                          } else if (w >= 900) {
                            crossAxisCount = 4;
                          } else if (w >= 650) {
                            crossAxisCount = 3;
                          }
                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 1,
                              crossAxisSpacing: 1,
                              childAspectRatio: () {
                                final spacing = 1.0;
                                final itemWidth =
                                    (w - spacing * (crossAxisCount - 1)) /
                                        crossAxisCount;
                                final ts =
                                    MediaQuery.of(context).textScaleFactor;
                                final baseMeta = 72.0;
                                final metaHeight = baseMeta +
                                    (ts > 1.0 ? (ts - 1.0) * 14.0 : 0.0);
                                final itemHeight = itemWidth + metaHeight;
                                return itemWidth / itemHeight;
                              }(),
                            ),
                            padding: const EdgeInsets.only(bottom: 48),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return _PharmacieDrugCard(
                                item: item,
                                loadPresentation: _loadPresentation,
                                loadEntries: _loadEntries,
                                onOpen: () {
                                  if (item.cip13.startsWith('custom:')) {
                                    context.pushNamed('custom_detail',
                                        queryParameters: {'key': item.cip13});
                                  } else {
                                    context.pushNamed('presentation_detail',
                                        pathParameters: {'cip13': item.cip13});
                                  }
                                },
                              );
                            },
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}

// InventoryItem is provided by PharmacieStore

class _PharmacieDrugCard extends StatefulWidget {
  final InventoryItem item;
  final Future<Map<String, dynamic>?> Function(String cip13) loadPresentation;
  final Future<List<InventoryEntry>> Function(String cip13) loadEntries;
  final VoidCallback onOpen;

  const _PharmacieDrugCard({
    required this.item,
    required this.loadPresentation,
    required this.loadEntries,
    required this.onOpen,
  });

  @override
  State<_PharmacieDrugCard> createState() => _PharmacieDrugCardState();
}

class _PharmacieDrugCardState extends State<_PharmacieDrugCard> {
  Future<List<InventoryEntry>>? _entriesFuture;
  bool _suppressNextTap = false; // set when image long-press is handled
  bool _imgPressed = false;

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.loadEntries(widget.item.cip13);
  }

  bool _hasExpired(List<InventoryEntry> entries) {
    final now = DateTime.now();
    for (final e in entries) {
      final ex = e.expiresAt;
      if (ex == null) continue;
      final eKey = ex.year * 100 + ex.month;
      final nKey = now.year * 100 + now.month;
      if (eKey < nKey) return true;
    }
    return false;
  }

  bool _hasExpiringThisMonth(List<InventoryEntry> entries) {
    final now = DateTime.now();
    for (final e in entries) {
      final ex = e.expiresAt;
      if (ex == null) continue;
      if (ex.year == now.year && ex.month == now.month) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>?>(
      future: widget.loadPresentation(widget.item.cip13),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final denomRaw = data != null && data['drugs'] != null
            ? (data['drugs']['denomination'] as String? ?? '')
            : '';
        final forme = data != null && data['drugs'] != null
            ? (data['drugs']['forme'] as String? ?? '')
            : '';
        final libelle = data != null ? (data['libelle'] as String? ?? '') : '';
        final split = DrugTextUtils.splitTitleSubtitle(denomRaw);
        final title = split.$1.isNotEmpty
            ? split.$1
            : (DrugTextUtils.sanitizeDenomination(denomRaw, forme).isNotEmpty
                ? DrugTextUtils.sanitizeDenomination(denomRaw, forme)
                : libelle);
        final subtitle = split.$2;

        return GestureDetector(
          onTap: () {
            if (_suppressNextTap) {
              setState(() => _suppressNextTap = false);
              return; // prevent navigating after long-press
            }
            widget.onOpen();
          },
          child: Card(
            color: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Square image with rounded corners and press animation
                Padding(
                  padding: const EdgeInsets.all(1),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    width: 0.6,
                                    color: scheme.outlineVariant
                                        .withOpacity(0.35)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: FutureBuilder<Uint8List?>(
                                  future: DrugPhotoService.getCoverBytes(
                                      widget.item.cip13),
                                  builder: (context, imgSnap) {
                                    final bytes = imgSnap.data;
                                    Widget imageWidget;
                                    if (bytes != null && bytes.isNotEmpty) {
                                      imageWidget = Image.memory(bytes,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.low);
                                    } else {
                                      imageWidget = Container(
                                        decoration: BoxDecoration(
                                            gradient:
                                                AppGradients.imagePlaceholder(
                                                    scheme)),
                                        child: Center(
                                          child: Icon(
                                              Icons.medication_liquid_outlined,
                                              size: 48,
                                              color: scheme.onPrimaryContainer),
                                        ),
                                      );
                                    }
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (_) => setState(() => _imgPressed = true),
                                      onTapUp: (_) => setState(() => _imgPressed = false),
                                      onTapCancel: () => setState(() => _imgPressed = false),
                                      onLongPress: () async {
                                        final bytes = await DrugPhotoService
                                            .getCoverBytes(widget.item.cip13);
                                        setState(() => _suppressNextTap = true);
                                        if (bytes != null && bytes.isNotEmpty) {
                                          BoxImageFullscreen.show(context,
                                              bytes: bytes);
                                        }
                                        Future.delayed(
                                            const Duration(milliseconds: 300),
                                            () {
                                          if (!mounted) return;
                                          setState(() => _suppressNextTap = false);
                                        });
                                      },
                                      onTap: () {
                                        if (_suppressNextTap) {
                                          setState(() => _suppressNextTap = false);
                                          return; // avoid navigating right after a long-press
                                        }
                                        widget.onOpen();
                                      },
                                      child: AnimatedScale(
                                        scale: _imgPressed ? 0.98 : 1,
                                        duration:
                                            const Duration(milliseconds: 120),
                                        curve: Curves.easeOut,
                                        child: imageWidget,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (widget.item.cip13.startsWith('custom:'))
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.back_hand,
                                    size: 16, color: scheme.onPrimary),
                              ),
                            ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: FutureBuilder<List<InventoryEntry>>(
                              future: _entriesFuture,
                              builder: (context, snap) {
                                final entries =
                                    snap.data ?? const <InventoryEntry>[];
                                final hasExpired = _hasExpired(entries);
                                final hasExpiring = !hasExpired &&
                                    _hasExpiringThisMonth(entries);
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasExpired || hasExpiring)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: Icon(
                                          hasExpired
                                              ? Icons.error_rounded
                                              : Icons.warning_amber_rounded,
                                          size: 18,
                                          color: hasExpired
                                              ? scheme.error
                                              : (Theme.of(context)
                                                      .extension<AppColors>()
                                                      ?.warning ??
                                                  Colors.orange),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: scheme.secondary,
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Text('x${widget.item.quantity}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.semiBold
                                              .withColor(scheme.onSecondary)),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Fixed-height text area for alignment
                SizedBox(
                  height: 72.0 +
                      ((MediaQuery.of(context).textScaleFactor > 1.0)
                          ? ((MediaQuery.of(context).textScaleFactor - 1.0) *
                              14.0)
                          : 0.0),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          DrugTextUtils.toTitleCase(
                              title.isNotEmpty ? title : '—'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.semiBold
                              .copyWith(
                                  fontSize: (Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.fontSize ??
                                          16) -
                                      2,
                                  height: 1.1),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.withColor(scheme.onSurfaceVariant)
                                .copyWith(
                                    fontSize:
                                        (Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.fontSize ??
                                            12) -
                                        1,
                                    height: 1.1),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PharmacieDrugListItem extends StatefulWidget {
  final InventoryItem item;
  final Future<Map<String, dynamic>?> Function(String cip13) loadPresentation;
  final Future<List<InventoryEntry>> Function(String cip13) loadEntries;
  final VoidCallback onOpen;

  const _PharmacieDrugListItem(
      {required this.item,
      required this.loadPresentation,
      required this.loadEntries,
      required this.onOpen});

  @override
  State<_PharmacieDrugListItem> createState() => _PharmacieDrugListItemState();
}

class _PharmacieDrugListItemState extends State<_PharmacieDrugListItem> {
  Future<List<InventoryEntry>>? _entriesFuture;
  bool _suppressNextTap = false; // set when image long-press is handled

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.loadEntries(widget.item.cip13);
  }

  bool _hasExpired(List<InventoryEntry> entries) {
    final now = DateTime.now();
    for (final e in entries) {
      final ex = e.expiresAt;
      if (ex == null) continue;
      final eKey = ex.year * 100 + ex.month;
      final nKey = now.year * 100 + now.month;
      if (eKey < nKey) return true;
    }
    return false;
  }

  bool _hasExpiringThisMonth(List<InventoryEntry> entries) {
    final now = DateTime.now();
    for (final e in entries) {
      final ex = e.expiresAt;
      if (ex == null) continue;
      if (ex.year == now.year && ex.month == now.month) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FutureBuilder<Map<String, dynamic>?>(
      future: widget.loadPresentation(widget.item.cip13),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final denomRaw = data != null && data['drugs'] != null
            ? (data['drugs']['denomination'] as String? ?? '')
            : '';
        final forme = data != null && data['drugs'] != null
            ? (data['drugs']['forme'] as String? ?? '')
            : '';
        final libelle = data != null ? (data['libelle'] as String? ?? '') : '';
        final split = DrugTextUtils.splitTitleSubtitle(denomRaw);
        final title = split.$1.isNotEmpty
            ? split.$1
            : (DrugTextUtils.sanitizeDenomination(denomRaw, forme).isNotEmpty
                ? DrugTextUtils.sanitizeDenomination(denomRaw, forme)
                : libelle);
        final subtitle = split.$2;

        return GestureDetector(
          onTap: () {
            if (_suppressNextTap) {
              setState(() => _suppressNextTap = false);
              return; // prevent navigating after long-press
            }
            widget.onOpen();
          },
          child: Card(
            color: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Image thumbnail with manual marker overlay
                  SizedBox(
                    width: 112,
                    height: 112,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _ListThumbPressable(
                            cip13: widget.item.cip13,
                            onImageOpen: (bytes) {
                              setState(() => _suppressNextTap = true);
                              BoxImageFullscreen.show(context, bytes: bytes);
                              Future.delayed(const Duration(milliseconds: 300), () {
                                if (!mounted) return;
                                setState(() => _suppressNextTap = false);
                              });
                            },
                            onTap: () {
                              if (_suppressNextTap) {
                                setState(() => _suppressNextTap = false);
                                return;
                              }
                              widget.onOpen();
                            },
                          ),
                        ),
                        if (widget.item.cip13.startsWith('custom:'))
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.back_hand,
                                  size: 14, color: scheme.onPrimary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Title + subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DrugTextUtils.toTitleCase(
                              title.isNotEmpty ? title : '—'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: (text.titleMedium?.semiBold)?.copyWith(
                            fontSize: (text.titleMedium?.fontSize ?? 16) + 1,
                            height: 1.1,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                ?.copyWith(
                                  fontSize:
                                      (text.bodySmall?.fontSize ?? 12) - 1,
                                  height: 1.1,
                                )
                                .withColor(scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Expiry alert + quantity badge (expiry icon to the left of counter)
                  FutureBuilder<List<InventoryEntry>>(
                    future: _entriesFuture,
                    builder: (context, snap) {
                      final entries = snap.data ?? const <InventoryEntry>[];
                      final hasExpired = _hasExpired(entries);
                      final hasExpiring =
                          !hasExpired && _hasExpiringThisMonth(entries);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasExpired || hasExpiring)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                hasExpired
                                    ? Icons.error_rounded
                                    : Icons.warning_amber_rounded,
                                size: 20,
                                color: hasExpired
                                    ? scheme.error
                                    : (Theme.of(context)
                                            .extension<AppColors>()
                                            ?.warning ??
                                        Colors.orange),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: scheme.secondary,
                                borderRadius: BorderRadius.circular(14)),
                            child: Text('x${widget.item.quantity}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.semiBold
                                    .withColor(scheme.onSecondary)),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ListThumbPressable extends StatefulWidget {
  final String cip13;
  final void Function(Uint8List bytes) onImageOpen;
  final VoidCallback? onTap;

  const _ListThumbPressable({required this.cip13, required this.onImageOpen, this.onTap});

  @override
  State<_ListThumbPressable> createState() => _ListThumbPressableState();
}

class _ListThumbPressableState extends State<_ListThumbPressable> {
  bool _imgPressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: DrugPhotoService.getCoverBytes(widget.cip13),
      builder: (context, imgSnap) {
        final bytes = imgSnap.data;
        final radius = BorderRadius.circular(12);
        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
                color: scheme.outlineVariant.withOpacity(0.35), width: 1),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _imgPressed = true),
              onTapUp: (_) => setState(() => _imgPressed = false),
              onTapCancel: () => setState(() => _imgPressed = false),
              onTap: widget.onTap,
              onLongPress: () {
                if (bytes != null && bytes.isNotEmpty) {
                  widget.onImageOpen(bytes);
                }
              },
              child: AnimatedScale(
                scale: _imgPressed ? 0.98 : 1,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: bytes != null && bytes.isNotEmpty
                    ? Image.memory(bytes,
                        fit: BoxFit.cover, filterQuality: FilterQuality.low)
                    : Container(
                        decoration: BoxDecoration(
                            gradient: AppGradients.imagePlaceholder(scheme)),
                        child: Center(
                            child: Icon(Icons.medication_liquid_outlined,
                                size: 32, color: scheme.onPrimaryContainer)),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
