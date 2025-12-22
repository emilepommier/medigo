import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/family_service.dart';

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

  // --- Entries API ---
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

  static Future<void> _addLocalEntries(String cip13, {int by = 1}) async {
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
        'expiresAt': null,
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
          final rows = await SupabaseConfig.client
              .from('pharmacy_items')
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

  static Future<void> addOrIncrement(String cip13, {int by = 1}) async {
    // Remote first if logged in
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          // Fetch current quantity once to decide between insert/update
          final current = await SupabaseConfig.client
              .from('pharmacy_items')
              .select('quantity')
              .eq('family_id', familyId)
              .eq('cip13', cip13)
              .maybeSingle();
          if (current == null) {
            // Insert with the exact requested quantity to avoid default=1 double count
            await SupabaseConfig.client.from('pharmacy_items').insert({
              'family_id': familyId,
              'cip13': cip13,
              'quantity': by,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          } else {
            final cur = (current['quantity'] as num).toInt();
            final newQty = cur + by;
            await SupabaseConfig.client
                .from('pharmacy_items')
                .update({'quantity': newQty, 'updated_at': DateTime.now().toUtc().toIso8601String()})
                .eq('family_id', familyId)
                .eq('cip13', cip13);
          }
          // Attempt to record per-box entries remotely as well
          try {
            final now = DateTime.now().toUtc().toIso8601String();
            final rows = List.generate(by, (_) => {
                  'family_id': familyId,
                  'cip13': cip13,
                  'added_at': now,
                });
            await SupabaseConfig.client.from('pharmacy_item_entries').insert(rows);
          } catch (e) {
            debugPrint('PharmacieStore.remote entries insert failed (will fallback local): $e');
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
    await _addLocalEntries(cip13, by: by);
  }

  static Future<void> decrementOrRemove(String cip13, {int by = 1}) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          final row = await SupabaseConfig.client
              .from('pharmacy_items')
              .select('quantity')
              .eq('family_id', familyId)
              .eq('cip13', cip13)
              .maybeSingle();
          final cur = (row != null ? (row['quantity'] as num).toInt() : 0);
          final newQty = cur - by;
          if (newQty <= 0) {
            await SupabaseConfig.client
                .from('pharmacy_items')
                .delete()
                .eq('family_id', familyId)
                .eq('cip13', cip13);
          } else {
            await SupabaseConfig.client
                .from('pharmacy_items')
                .update({'quantity': newQty, 'updated_at': DateTime.now().toUtc().toIso8601String()})
                .eq('family_id', familyId)
                .eq('cip13', cip13);
          }
          // Attempt to remove last N entries remotely
          try {
            final entries = await SupabaseConfig.client
                .from('pharmacy_item_entries')
                .select('id')
                .eq('family_id', familyId)
                .eq('cip13', cip13)
                .order('added_at', ascending: false)
                .limit(by);
            final ids = (entries as List).map((e) => e['id']).toList();
            if (ids.isNotEmpty) {
              await SupabaseConfig.client
                  .from('pharmacy_item_entries')
                  .delete()
                  .inFilter('id', ids);
            }
          } catch (e) {
            debugPrint('PharmacieStore.remote entries delete failed (will fallback local): $e');
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
  }

  static Future<void> remove(String cip13) async {
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final familyId = await FamilyService.getCurrentFamilyId();
        if (familyId != null) {
          await SupabaseConfig.client
              .from('pharmacy_items')
              .delete()
              .eq('family_id', familyId)
              .eq('cip13', cip13);
          return;
        }
      } catch (e) {
        debugPrint('PharmacieStore.remote remove failed: $e');
      }
    }
    final list = await load();
    list.removeWhere((e) => e.cip13 == cip13);
    await _save(list);
  }
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

  static Future<void> _addLocalEntries(String cip13, {int by = 1}) async {
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
        'expiresAt': null,
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
}
*/

