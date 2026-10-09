import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/limit_entry.dart';

/// Service for managing buy limit tracking.
/// 
/// Stores limit entries in shared_preferences as JSON.
/// The window duration is 4 hours as per OSRS GE mechanics.
/// 
/// NOTE: manual tracking - the game API does not expose remaining buy limits.
class LimitService {
  static const String _storageKey = 'buy_limit_entries';
  static const Duration windowDuration = Duration(hours: 4);

  final SharedPreferences _prefs;

  LimitService(this._prefs);

  /// Factory constructor that initializes SharedPreferences.
  static Future<LimitService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LimitService(prefs);
  }

  /// Loads all limit entries from storage.
  List<LimitEntry> loadEntries() {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return <LimitEntry>[];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((e) => LimitEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      return <LimitEntry>[];
    }
  }

  /// Saves all limit entries to storage.
  Future<void> _saveEntries(List<LimitEntry> entries) async {
    final jsonList = entries.map((e) => e.toJson()).toList();
    await _prefs.setString(_storageKey, json.encode(jsonList));
  }

  /// Gets an entry for a specific item, if it exists and is not expired.
  LimitEntry? getActiveEntry(int itemId) {
    final entries = loadEntries();
    try {
      final entry = entries.firstWhere((e) => e.itemId == itemId);
      if (entry.isExpired(windowDuration)) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  /// Gets all active (non-expired) entries.
  List<LimitEntry> getActiveEntries() {
    return loadEntries()
        .where((e) => !e.isExpired(windowDuration))
        .toList();
  }

  /// Adds or updates a purchase quantity for an item.
  /// 
  /// If no entry exists for the item, creates a new entry with the given quantity.
  /// If an active window exists (< 4h), adds the quantity to it.
  /// If the window has expired, starts a new window with the given quantity.
  Future<LimitEntry> trackPurchase({
    required int itemId,
    required String itemName,
    required int quantity,
    required int currentLimit,
  }) async {
    final entries = loadEntries();
    final existingIndex = entries.indexWhere((e) => e.itemId == itemId);

    LimitEntry newEntry;

    if (existingIndex == -1) {
      // No entry exists - create new window
      newEntry = LimitEntry(
        itemId: itemId,
        itemName: itemName,
        quantityBought: quantity,
        windowStart: DateTime.now().millisecondsSinceEpoch,
        limit: currentLimit,
      );
      entries.add(newEntry);
    } else {
      final existing = entries[existingIndex];
      if (existing.isExpired(windowDuration)) {
        // Window expired - start new window
        newEntry = existing.startNewWindow(quantity, currentLimit);
        entries[existingIndex] = newEntry;
      } else {
        // Active window - add quantity
        newEntry = existing.addQuantity(quantity);
        entries[existingIndex] = newEntry;
      }
    }

    await _saveEntries(entries);
    return newEntry;
  }

  /// Removes a specific item's tracking entry.
  Future<void> removeEntry(int itemId) async {
    final entries = loadEntries();
    entries.removeWhere((e) => e.itemId == itemId);
    await _saveEntries(entries);
  }

  /// Manually resets the tracking window for an item.
  /// This effectively deletes the entry, allowing a fresh start.
  Future<void> resetEntry(int itemId) async {
    await removeEntry(itemId);
  }

  /// Cleans up expired windows from storage.
  /// Returns the number of entries that were removed.
  Future<int> cleanupExpired() async {
    final entries = loadEntries();
    final originalCount = entries.length;
    entries.removeWhere((e) => e.isExpired(windowDuration));
    await _saveEntries(entries);
    return originalCount - entries.length;
  }
}