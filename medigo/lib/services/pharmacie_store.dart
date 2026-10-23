import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/family_service.dart';
import 'package:medigo/services/drug_photo_service.dart';

class InventoryItem {
  final String cip13;
  final int quantity;

  const InventoryItem({required this.cip13, required this.quantity});

  InventoryItem copyWith({String? cip13, int? quantity}) =>
      InventoryItem(cip13: cip13 ?? this.cip13, quantity: quantity ?? this.quantity);

  Map<String, dynamic> toJson() => {
        'cip13': cip13,
        'quantity': quantity,
      };

  static InventoryItem? fromJson(dynamic json) {
    try {
      final map = json as Map<String, dynamic>;
      final cip = map['cip13'] as String?;
      final qty = map['quantity'] is int
          ? map['quantity'] as int
          : int.tryParse(map['quantity']?.toString() ?? '');
      if (cip == null || qty == null) return null;
      return InventoryItem(cip13: cip, quantity: qty);
    } catch (e) {
      debugPrint('Corrupted inventory item skipped: $e');
      return null;
    }
  }
}

class PharmacieStore {
  PharmacieStore._();
  static const String _prefsKey = 'pharmacie_items';
  static const String _prefsEntriesKey = 'pharmacie_entries';
  static const String _prefsCustomMetaKey = 'pharmacie_custom_meta';
  // Cached feature flag: whether the remote entries table exists
  static bool _entriesTableAvailable = true;

  // Broadcast local change notifications so UI can refresh instantly
  static final StreamController<void> _changesController = StreamController<void>.broadcast();
  static Stream<void> get changes => _changesController.stream;
  static void _emitChange() {
    try {
      _changesController.add(null);
    } catch (_) {}
  }

  // --- Entries API ---
  static Future<List<InventoryEntry>> loadEntries(String cip13) async {
    // Remote ONLY when authenticated; do NOT fallback to local when logged in
    if (SupabaseConfig.auth.currentUser != null) {
      if (_entriesTableAvailable) {
        try {
          final familyId = await FamilyService.getCurrentFamilyId();
          if (familyId != null) {
            final rows = await SupabaseConfig.client
                .from('pharmacy_item_entries')
                .select('id,cip13,added_at,expires_at,photo_url')
                .eq('family_id', familyId)
                .eq('cip13', cip13)
                .order('added_at', ascending: false);
            final list = (rows as List)
                .map((e) => InventoryEntry(
                      id: e['id'].toString(),
                      cip13: e['cip13'] as String,
                      addedAt: DateTime.parse(e['added_at'] as String),
                      expiresAt: (e['expires_at'] != null) ? DateTime.tryParse(e['expires_at'] as String) : null,
                      photoUrl: e['photo_url'] as String?,
                    ))
                .toList();
            return list;
          }
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
            _entriesTableAvailable = false;
          } else {
            debugPrint('PharmacieStore.remote loadEntries failed: $e');
          }
        }
      }
      // Authenticated but entries table not available -> return empty; caller may synthesize placeholders
      return [];
    }
    // Not authenticated -> use local storage for entries
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsEntriesKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final listRaw = (decoded[cip13] as List?) ?? [];
      final list = listRaw.map((e) => InventoryEntry.fromJson(e)).whereType<InventoryEntry>().toList();
      return list;
    } catch (e) {
      debugPrint('PharmacieStore.loadEntries failed: $e');
      return [];
    }
  }

  /// Display-friendly loader: never uses local storage when authenticated.
  /// If the entries table is unavailable remotely, it returns ephemeral placeholders
  /// based on the remote aggregate quantity so UI stays in sync with Home.
  static Future<List<InventoryEntry>> loadEntriesForDisplay(String cip13) async {
    if (SupabaseConfig.auth.currentUser != null) {
      // Try remote entries first
      final entries = await loadEntries(cip13);
      if (entries.isNotEmpty || _entriesTableAvailable) return entries;
      // Entries table unavailable -> synthesize placeholders using aggregate quantity
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          final row = await SupabaseConfig.client
              .from('pharmacy_items_view')
              .select('quantity')
              .eq('family_id', familyId)
              .eq('cip13', cip13)
              .maybeSingle();
          final qty = row == null ? 0 : (row['quantity'] as num).toInt();
          final now = DateTime.now();
          return List.generate(qty, (i) => InventoryEntry(
                id: 'placeholder-$i',
                cip13: cip13,
                addedAt: now,
                expiresAt: null,
                photoUrl: null,
              ));
        }
      } catch (e) {
        debugPrint('PharmacieStore.loadEntriesForDisplay failed to synthesize: $e');
      }
      return const [];
    }
    // Not authenticated -> use local
    return loadEntries(cip13);
  }

  static Future<void> addEntry(String cip13, {DateTime? expiresAt, String? photoUrl}) async {
    // Remote preferred; if authenticated but table missing, do NOT store locally
    if (SupabaseConfig.auth.currentUser != null) {
      if (_entriesTableAvailable) {
        try {
          final familyId = await FamilyService.getCurrentFamilyId();
          if (familyId != null) {
            await SupabaseConfig.client.from('pharmacy_item_entries').insert({
              'family_id': familyId,
              'cip13': cip13,
              'added_at': DateTime.now().toUtc().toIso8601String(),
              'expires_at': expiresAt?.toUtc().toIso8601String(),
              'photo_url': photoUrl,
            });
            _emitChange();
            return;
          }
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
            _entriesTableAvailable = false;
          } else {
            debugPrint('PharmacieStore.remote addEntry failed: $e');
          }
        }
      }
      // Authenticated but entries table unavailable -> no local write
      return;
    }
    // Not authenticated -> Local persistence
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = InventoryEntry(id: id, cip13: cip13, addedAt: DateTime.now(), expiresAt: expiresAt, photoUrl: photoUrl);
    final list = ((map[cip13] as List?) ?? []).toList();
    list.insert(0, entry.toJson());
    map[cip13] = list;
    await prefs.setString(_prefsEntriesKey, jsonEncode(map));
    _emitChange();
  }

  /// Set a cover photo path for all entries of a cip13 for the current family (remote only).
  static Future<void> setPhotoForCip(String cip13, String photoPath) async {
    if (SupabaseConfig.auth.currentUser == null) return;
    try {
      final familyId = await FamilyService.getCurrentFamilyId();
      if (familyId == null) return;
      await SupabaseConfig.client
          .from('pharmacy_item_entries')
          .update({'photo_url': photoPath})
          .eq('family_id', familyId)
          .eq('cip13', cip13);
      try { DrugPhotoService.invalidateCache(cip13); } catch (_) {}
      _emitChange();
    } catch (e) {
      debugPrint('PharmacieStore.setPhotoForCip failed: $e');
    }
  }

  /// Clear the cover photo from all entries of a cip13 (remote only).
  static Future<void> clearPhotoForCip(String cip13) async {
    if (SupabaseConfig.auth.currentUser == null) return;
    try {
      final familyId = await FamilyService.getCurrentFamilyId();
      if (familyId == null) return;
      await SupabaseConfig.client
          .from('pharmacy_item_entries')
          .update({'photo_url': null})
          .eq('family_id', familyId)
          .eq('cip13', cip13);
      try { DrugPhotoService.invalidateCache(cip13); } catch (_) {}
      _emitChange();
    } catch (e) {
      debugPrint('PharmacieStore.clearPhotoForCip failed: $e');
    }
  }

  /// Create or ensure a custom manual item exists, then add one entry with expiry date.
  /// Returns the synthetic custom key (e.g., 'custom:...') on success, null otherwise.
  static Future<String?> addCustomManualItem({
    required String name,
    String? laboratory,
    String? forme,
    required DateTime expiresAt,
  }) async {
    try {
      // Remote preferred
      if (SupabaseConfig.auth.currentUser != null) {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId == null) return null;
        // Insert meta and get the generated custom_key
        final inserted = await SupabaseConfig.client
            .from('custom_items')
            .insert({
              'family_id': familyId,
              'name': name,
              if (laboratory != null && laboratory.isNotEmpty) 'laboratory': laboratory,
              if (forme != null && forme.isNotEmpty) 'forme': forme,
            })
            .select('custom_key')
            .single();
        final customKey = (inserted)['custom_key']?.toString();
        if (customKey == null) return null;
        // Add one entry into pharmacy_item_entries using the synthetic key
        if (_entriesTableAvailable) {
          try {
            await SupabaseConfig.client.from('pharmacy_item_entries').insert({
              'family_id': familyId,
              'cip13': customKey,
              'added_at': DateTime.now().toUtc().toIso8601String(),
              'expires_at': expiresAt.toUtc().toIso8601String(),
            });
            _emitChange();
          } catch (e) {
            final msg = e.toString();
            if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
              _entriesTableAvailable = false;
            } else {
              debugPrint('PharmacieStore.remote addCustomManualItem entry insert failed: $e');
            }
          }
        }
        return customKey;
      }

      // Local fallback when not authenticated
      final customKey = 'custom:${DateTime.now().millisecondsSinceEpoch}';
      try {
        final prefs = await SharedPreferences.getInstance();
        // Save meta locally
        Map<String, dynamic> meta = {};
        final rawMeta = prefs.getString(_prefsCustomMetaKey);
        if (rawMeta != null) {
          try {
            meta = (jsonDecode(rawMeta) as Map).map((k, v) => MapEntry(k.toString(), v));
          } catch (_) {}
        }
        meta[customKey] = {
          'name': name,
          if (laboratory != null) 'laboratory': laboratory,
          if (forme != null) 'forme': forme,
        };
        await prefs.setString(_prefsCustomMetaKey, jsonEncode(meta));

        // Save aggregate locally
        final items = await load();
        final idx = items.indexWhere((e) => e.cip13 == customKey);
        if (idx >= 0) {
          items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
        } else {
          items.add(InventoryItem(cip13: customKey, quantity: 1));
        }
        await _save(items);
        // Add local entry with expiry
        await _addLocalEntries(customKey, by: 1, expiresAt: expiresAt);
        _emitChange();
      } catch (e) {
        debugPrint('PharmacieStore.local addCustomManualItem failed: $e');
      }
      return customKey;
    } catch (e) {
      debugPrint('PharmacieStore.addCustomManualItem failed: $e');
      return null;
    }
  }

  /// Load metadata for a custom manual item by synthetic key.
  static Future<Map<String, dynamic>?> loadCustomMeta(String customKey) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          final row = await SupabaseConfig.client
              .from('custom_items')
              .select('custom_key,name,laboratory,forme,photo_url')
              .eq('family_id', familyId)
              .eq('custom_key', customKey)
              .maybeSingle();
          return row;
        }
      } catch (e) {
        debugPrint('PharmacieStore.loadCustomMeta failed: $e');
      }
      return null;
    }
    // Local fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsCustomMetaKey);
      if (raw == null) return null;
      final meta = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      final m = meta[customKey] as Map<String, dynamic>?;
      if (m == null) return null;
      return {
        'custom_key': customKey,
        'name': m['name'],
        'laboratory': m['laboratory'],
        'forme': m['forme'],
        'photo_url': m['photo_url'],
      };
    } catch (e) {
      debugPrint('PharmacieStore.loadCustomMeta local failed: $e');
      return null;
    }
  }

  /// Update custom manual item metadata (name, laboratory, forme)
  static Future<bool> updateCustomMeta({
    required String customKey,
    String? name,
    String? laboratory,
    String? forme,
  }) async {
    try {
      if (SupabaseConfig.auth.currentUser != null) {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId == null) return false;
        final payload = <String, dynamic>{};
        if (name != null) payload['name'] = name;
        if (laboratory != null) payload['laboratory'] = laboratory;
        if (forme != null) payload['forme'] = forme;
        if (payload.isEmpty) return true; // nothing to update
        await SupabaseConfig.client
            .from('custom_items')
            .update(payload)
            .eq('family_id', familyId)
            .eq('custom_key', customKey);
        return true;
      }
      // Local fallback when not authenticated
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> meta = {};
      final rawMeta = prefs.getString(_prefsCustomMetaKey);
      if (rawMeta != null) {
        try {
          meta = (jsonDecode(rawMeta) as Map).map((k, v) => MapEntry(k.toString(), v));
        } catch (_) {}
      }
      final m = ((meta[customKey] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v));
      if (name != null) m['name'] = name;
      if (laboratory != null) m['laboratory'] = laboratory;
      if (forme != null) m['forme'] = forme;
      meta[customKey] = m;
      await prefs.setString(_prefsCustomMetaKey, jsonEncode(meta));
      return true;
    } catch (e) {
      debugPrint('PharmacieStore.updateCustomMeta failed: $e');
      return false;
    }
  }

  /// Update photo_url for a custom manual item.
  static Future<bool> updateCustomPhoto({required String customKey, String? photoPath}) async {
    try {
      if (SupabaseConfig.auth.currentUser != null) {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId == null) return false;
        await SupabaseConfig.client
            .from('custom_items')
            .update({'photo_url': photoPath})
            .eq('family_id', familyId)
            .eq('custom_key', customKey);
        return true;
      }
      // Local fallback: store photo path in local meta for manual items
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> meta = {};
      final rawMeta = prefs.getString(_prefsCustomMetaKey);
      if (rawMeta != null) {
        try {
          meta = (jsonDecode(rawMeta) as Map).map((k, v) => MapEntry(k.toString(), v));
        } catch (_) {}
      }
      final m = ((meta[customKey] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v));
      m['photo_url'] = photoPath;
      meta[customKey] = m;
      await prefs.setString(_prefsCustomMetaKey, jsonEncode(meta));
      return true;
    } catch (e) {
      debugPrint('PharmacieStore.updateCustomPhoto failed: $e');
      return false;
    }
  }

  static Future<void> updateEntry(String id, String cip13, {DateTime? expiresAt, String? photoUrl}) async {
    // Remote preferred; if authenticated but entries table missing, do NOT update locally
    if (SupabaseConfig.auth.currentUser != null) {
      if (_entriesTableAvailable) {
        try {
          final familyId = await FamilyService.getCurrentFamilyId();
          if (familyId != null) {
            await SupabaseConfig.client
                .from('pharmacy_item_entries')
                .update({
                  if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
                  if (photoUrl != null) 'photo_url': photoUrl,
                })
                .eq('id', id)
                .eq('family_id', familyId);
            _emitChange();
            return;
          }
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
            _entriesTableAvailable = false;
          } else {
            debugPrint('PharmacieStore.remote updateEntry failed: $e');
          }
        }
      }
      return;
    }
    // Not authenticated -> Local update
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      final list = ((map[cip13] as List?) ?? []).toList();
      for (var i = 0; i < list.length; i++) {
        final e = list[i] as Map<String, dynamic>;
        if (e['id'].toString() == id) {
          if (expiresAt != null) e['expiresAt'] = expiresAt.toIso8601String();
          if (photoUrl != null) e['photoUrl'] = photoUrl;
          list[i] = e;
          break;
        }
      }
      map[cip13] = list;
      await prefs.setString(_prefsEntriesKey, jsonEncode(map));
    } catch (e) {
      debugPrint('PharmacieStore.updateEntry local failed: $e');
    }
    _emitChange();
  }

  static Future<void> _addLocalEntries(String cip13, {int by = 1, DateTime? expiresAt}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    final now = DateTime.now();
    final list = ((map[cip13] as List?) ?? []).toList();
    for (int i = 0; i < by; i++) {
      final id = '${now.millisecondsSinceEpoch}-${i.toString()}';
      list.insert(0, {
        'id': id,
        'cip13': cip13,
        'addedAt': now.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'photoUrl': null,
      });
    }
    map[cip13] = list;
    await prefs.setString(_prefsEntriesKey, jsonEncode(map));
  }

  static Future<void> _removeLocalEntries(String cip13, {int by = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      final list = ((map[cip13] as List?) ?? []).toList();
      int removed = 0;
      while (list.isNotEmpty && removed < by) {
        list.removeAt(0); // remove newest first
        removed++;
      }
      map[cip13] = list;
      await prefs.setString(_prefsEntriesKey, jsonEncode(map));
    } catch (e) {
      debugPrint('PharmacieStore._removeLocalEntries failed: $e');
    }
  }

  static Future<List<InventoryItem>> load() async {
    // If authenticated and user has a family, load from Supabase
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          if (_entriesTableAvailable) {
            try {
              final rows = await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .select('cip13')
                  .eq('family_id', familyId);
              // Count per cip13 in Dart to keep Home in sync with Detail
              final counts = <String, int>{};
              for (final r in (rows as List)) {
                final c = (r as Map<String, dynamic>)['cip13']?.toString();
                if (c == null) continue;
                counts[c] = (counts[c] ?? 0) + 1;
              }
              final list = counts.entries.map((e) => InventoryItem(cip13: e.key, quantity: e.value)).toList();
              // Keep a stable ordering by cip or by quantity desc
              list.sort((a, b) => b.quantity.compareTo(a.quantity));
              return list;
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote load (entries-based) failed: $e');
              }
              // fallthrough to pharmacy_items below
            }
          }
          // Fallback: use aggregate view
          final rows = await SupabaseConfig.client
              .from('pharmacy_items_view')
              .select('cip13, quantity')
              .eq('family_id', familyId)
              .order('updated_at', ascending: false);
          final list = (rows as List)
              .map((e) => InventoryItem(cip13: e['cip13'] as String, quantity: (e['quantity'] as num).toInt()))
              .toList();
          return list;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote load failed: $e');
      }
    }

    // Fallback to local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = decoded.map((e) => InventoryItem.fromJson(e)).whereType<InventoryItem>().toList();
      // Sanitize and write back to avoid re-failing on next load
      await prefs.setString(_prefsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
      return items;
    } catch (e) {
      debugPrint('PharmacieStore.load failed: $e');
      // write back empty list if corrupted
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode([]));
      return [];
    }
  }

  static Future<void> _save(List<InventoryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('PharmacieStore.save failed: $e');
    }
  }

  static Future<void> addOrIncrement(String cip13, {int by = 1, DateTime? expiresAt}) async {
    // Remote first if logged in
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Insert per-box entries (source of truth)
          if (_entriesTableAvailable) {
            try {
              final now = DateTime.now().toUtc().toIso8601String();
              final rows = List.generate(by, (_) => {
                    'family_id': familyId,
                    'cip13': cip13,
                    'added_at': now,
                    if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
                  });
              await SupabaseConfig.client.from('pharmacy_item_entries').insert(rows);
              _emitChange();
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote entries insert failed: $e');
              }
            }
          }
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote addOrIncrement failed: $e');
      }
    }
    // Local fallback
    final list = await load();
    final idx = list.indexWhere((e) => e.cip13 == cip13);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(quantity: list[idx].quantity + by);
    } else {
      list.add(InventoryItem(cip13: cip13, quantity: by));
    }
    await _save(list);
    // Local entries tracking
    await _addLocalEntries(cip13, by: by, expiresAt: expiresAt);
    _emitChange();
  }

  static Future<void> decrementOrRemove(String cip13, {int by = 1}) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Remove last N entries (most recently added)
          if (_entriesTableAvailable) {
            try {
              final entries = await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .select('id,photo_url')
                  .eq('family_id', familyId)
                  .eq('cip13', cip13)
                  .order('added_at', ascending: false)
                  .limit(by);
              final list = (entries as List).cast<Map<String, dynamic>>();
              final ids = list.map((e) => e['id']).toList();
              if (ids.isNotEmpty) {
                await SupabaseConfig.client.from('pharmacy_item_entries').delete().inFilter('id', ids);
                // After deletion, if no entries remain for this cip, also clear any cover photo path
                try {
                  final remain = await SupabaseConfig.client
                      .from('pharmacy_item_entries')
                      .select('id')
                      .eq('family_id', familyId)
                      .eq('cip13', cip13)
                      .limit(1);
                  final count = (remain as List).length; // rows length after limit 1
                  if (count == 0) {
                    // Clear photo_url fields (best effort). We will also delete the storage object in remove().
                    await SupabaseConfig.client
                        .from('pharmacy_item_entries')
                        .update({'photo_url': null})
                        .eq('family_id', familyId)
                        .eq('cip13', cip13);
                    try { await DrugPhotoService.deleteCoverByCipKey(cip13); } catch (_) {}
                    try { DrugPhotoService.invalidateCache(cip13); } catch (_) {}
                    if (cip13.startsWith('custom:')) { try { await updateCustomPhoto(customKey: cip13, photoPath: null); } catch (_) {} }
                  }
                } catch (e) {
                  debugPrint('Post-delete remain check failed: $e');
                }
                _emitChange();
              }
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote entries delete failed: $e');
              }
            }
          }
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote decrementOrRemove failed: $e');
      }
    }
    // Local fallback
    final list = await load();
    final idx = list.indexWhere((e) => e.cip13 == cip13);
    if (idx >= 0) {
      final q = list[idx].quantity - by;
      if (q <= 0) {
        list.removeAt(idx);
      } else {
        list[idx] = list[idx].copyWith(quantity: q);
      }
      await _save(list);
    }
    await _removeLocalEntries(cip13, by: by);
    _emitChange();
  }

  static Future<void> remove(String cip13) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Delete all entries for this cip13
          if (_entriesTableAvailable) {
            try {
              // Best-effort: clear photo_url and delete deterministic cover object
              try {
                await SupabaseConfig.client
                    .from('pharmacy_item_entries')
                    .update({'photo_url': null})
                    .eq('family_id', familyId)
                    .eq('cip13', cip13);
              } catch (_) {}
              await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .delete()
                  .eq('family_id', familyId)
                  .eq('cip13', cip13);
              // Best effort: delete the deterministic cover object as well
              try { await DrugPhotoService.deleteCoverByCipKey(cip13); } catch (_) {}
              // Clear custom item photo meta if this is a custom item
              if (cip13.startsWith('custom:')) {
                try { await updateCustomPhoto(customKey: cip13, photoPath: null); } catch (_) {}
              }
              try { DrugPhotoService.invalidateCache(cip13); } catch (_) {}
              _emitChange();
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote remove entries failed: $e');
              }
            }
          }
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote remove failed: $e');
      }
    }
    final list = await load();
    list.removeWhere((e) => e.cip13 == cip13);
    await _save(list);
    _emitChange();
  }

  /// Remove a specific per-box entry by id and decrement the aggregate quantity.
  static Future<void> removeEntry(String cip13, String entryId) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Delete the specific entry record
          if (_entriesTableAvailable) {
            try {
              await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .delete()
                  .eq('id', entryId)
                  .eq('family_id', familyId);
              // If it was the last entry, clear residual photo_url links
              try {
                final remain = await SupabaseConfig.client
                    .from('pharmacy_item_entries')
                    .select('id')
                    .eq('family_id', familyId)
                    .eq('cip13', cip13)
                    .limit(1);
                final count = (remain as List).length;
                if (count == 0) {
                  await SupabaseConfig.client
                      .from('pharmacy_item_entries')
                      .update({'photo_url': null})
                      .eq('family_id', familyId)
                      .eq('cip13', cip13);
                  try { await DrugPhotoService.deleteCoverByCipKey(cip13); } catch (_) {}
                  try { DrugPhotoService.invalidateCache(cip13); } catch (_) {}
                  if (cip13.startsWith('custom:')) { try { await updateCustomPhoto(customKey: cip13, photoPath: null); } catch (_) {} }
                }
              } catch (e) {
                debugPrint('Post single delete remain check failed: $e');
              }
              _emitChange();
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote removeEntry failed: $e');
              }
            }
          }
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote removeEntry aggregate failed: $e');
      }
    }

    // Local fallback: decrement aggregate and remove entry by id
    final items = await load();
    final idx = items.indexWhere((e) => e.cip13 == cip13);
    if (idx >= 0) {
      final q = items[idx].quantity - 1;
      if (q <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(quantity: q);
      }
      await _save(items);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsEntriesKey);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
        final list = ((map[cip13] as List?) ?? []).toList();
        list.removeWhere((e) => (e as Map<String, dynamic>)['id'].toString() == entryId);
        map[cip13] = list;
        await prefs.setString(_prefsEntriesKey, jsonEncode(map));
      }
    } catch (e) {
      debugPrint('PharmacieStore.removeEntry local failed: $e');
    }
    _emitChange();
  }

  // Helper: remove a specific local entry by id for a cip13
}

class InventoryEntry {
  final String id;
  final String cip13;
  final DateTime addedAt;
  final DateTime? expiresAt;
  final String? photoUrl;

  const InventoryEntry({
    required this.id,
    required this.cip13,
    required this.addedAt,
    this.expiresAt,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'cip13': cip13,
        'addedAt': addedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'photoUrl': photoUrl,
      };

  static InventoryEntry? fromJson(dynamic json) {
    try {
      final m = json as Map<String, dynamic>;
      final id = m['id']?.toString();
      final cip13 = m['cip13']?.toString();
      final added = DateTime.tryParse(m['addedAt']?.toString() ?? '');
      final expires = m['expiresAt'] != null ? DateTime.tryParse(m['expiresAt'].toString()) : null;
      final photoUrl = m['photoUrl']?.toString();
      if (id == null || cip13 == null || added == null) return null;
      return InventoryEntry(id: id, cip13: cip13, addedAt: added, expiresAt: expires, photoUrl: photoUrl);
    } catch (e) {
      debugPrint('Corrupted entry skipped: $e');
      return null;
    }
  }
}

// Legacy extension placeholder removed; entries API is now part of PharmacieStore static methods above.
/*
extension PharmacieEntries on PharmacieStore {
  static Future<List<InventoryEntry>> loadEntries(String cip13) async {
    // Remote
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          final rows = await SupabaseConfig.client
              .from('pharmacy_item_entries')
              .select('id,cip13,added_at,expires_at,photo_url')
              .eq('family_id', familyId)
              .eq('cip13', cip13)
              .order('added_at', ascending: false);
          final list = (rows as List)
              .map((e) => InventoryEntry(
                    id: e['id'].toString(),
                    cip13: e['cip13'] as String,
                    addedAt: DateTime.parse(e['added_at'] as String),
                    expiresAt: (e['expires_at'] != null) ? DateTime.tryParse(e['expires_at'] as String) : null,
                    photoUrl: e['photo_url'] as String?,
                  ))
              .toList();
          return list;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote loadEntries failed: $e');
      }
    }
    // Local
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsEntriesKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final listRaw = (decoded[cip13] as List?) ?? [];
      final list = listRaw.map((e) => InventoryEntry.fromJson(e)).whereType<InventoryEntry>().toList();
      return list;
    } catch (e) {
      debugPrint('PharmacieStore.loadEntries failed: $e');
      return [];
    }
  }

  static Future<void> addEntry(String cip13, {DateTime? expiresAt, String? photoUrl}) async {
    // Remote
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          await SupabaseConfig.client.from('pharmacy_item_entries').insert({
            'family_id': familyId,
            'cip13': cip13,
            'added_at': DateTime.now().toUtc().toIso8601String(),
            'expires_at': expiresAt?.toUtc().toIso8601String(),
            'photo_url': photoUrl,
          });
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote addEntry failed: $e');
      }
    }
    // Local
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = InventoryEntry(
      id: id,
      cip13: cip13,
      addedAt: DateTime.now(),
      expiresAt: expiresAt,
      photoUrl: photoUrl,
    );
    final list = ((map[cip13] as List?) ?? []).toList();
    list.insert(0, entry.toJson());
    map[cip13] = list;
    await prefs.setString(_prefsEntriesKey, jsonEncode(map));
  }

  static Future<void> updateEntry(String id, String cip13, {DateTime? expiresAt, String? photoUrl}) async {
    // Remote
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          await SupabaseConfig.client
              .from('pharmacy_item_entries')
              .update({
                if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
                if (photoUrl != null) 'photo_url': photoUrl,
              })
              .eq('id', id)
              .eq('family_id', familyId);
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote updateEntry failed: $e');
      }
    }
    // Local
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      final list = ((map[cip13] as List?) ?? []).toList();
      for (var i = 0; i < list.length; i++) {
        final e = list[i] as Map<String, dynamic>;
        if (e['id'].toString() == id) {
          if (expiresAt != null) e['expiresAt'] = expiresAt.toIso8601String();
          if (photoUrl != null) e['photoUrl'] = photoUrl;
          list[i] = e;
          break;
        }
      }
      map[cip13] = list;
      await prefs.setString(_prefsEntriesKey, jsonEncode(map));
    } catch (e) {
      debugPrint('PharmacieStore.updateEntry local failed: $e');
    }
  }

  static Future<void> _addLocalEntries(String cip13, {int by = 1, DateTime? expiresAt}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    final now = DateTime.now();
    final list = ((map[cip13] as List?) ?? []).toList();
    for (int i = 0; i < by; i++) {
      final id = '${now.millisecondsSinceEpoch}-${i.toString()}';
      list.insert(0, {
        'id': id,
        'cip13': cip13,
        'addedAt': now.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'photoUrl': null,
      });
    }
    map[cip13] = list;
    await prefs.setString(_prefsEntriesKey, jsonEncode(map));
  }

  /// Remove a specific entry (box) by id and decrement the aggregate quantity accordingly.
  static Future<void> removeEntry(String cip13, String entryId) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Delete the specific entry if the entries table exists (source of truth)
          if (_entriesTableAvailable) {
            try {
              await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .delete()
                  .eq('id', entryId)
                  .eq('family_id', familyId);
              _emitChange();
            } catch (e) {
              final msg = e.toString();
              if (msg.contains('PGRST205') && msg.contains('pharmacy_item_entries')) {
                _entriesTableAvailable = false;
              } else {
                debugPrint('PharmacieStore.remote removeEntry failed: $e');
              }
            }
          }
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote removeEntry aggregate failed: $e');
      }
    }
    // Local fallback: decrement aggregate and remove matching entry id
    final items = await load();
    final idx = items.indexWhere((e) => e.cip13 == cip13);
    if (idx >= 0) {
      final q = items[idx].quantity - 1;
      if (q <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(quantity: q);
      }
      await _save(items);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsEntriesKey);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
        final list = ((map[cip13] as List?) ?? []).toList();
        list.removeWhere((e) => (e as Map<String, dynamic>)['id'].toString() == entryId);
        map[cip13] = list;
        await prefs.setString(_prefsEntriesKey, jsonEncode(map));
      }
    } catch (e) {
      debugPrint('PharmacieStore.removeEntry local failed: $e');
    }
  }

  static Future<void> _removeLocalEntries(String cip13, {int by = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsEntriesKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v));
      final list = ((map[cip13] as List?) ?? []).toList();
      int removed = 0;
      while (list.isNotEmpty && removed < by) {
        list.removeAt(0); // remove newest first
        removed++;
      }
      map[cip13] = list;
      await prefs.setString(_prefsEntriesKey, jsonEncode(map));
    } catch (e) {
      debugPrint('PharmacieStore._removeLocalEntries failed: $e');
    }
  }
}
*/

