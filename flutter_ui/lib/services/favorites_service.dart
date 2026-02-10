/// Favorites Service — Persist starred audio files
///
/// Singleton service for managing favorite audio files across sessions.
/// Uses SharedPreferences for persistence.
///
/// SL-RP-P1.5: Favorites System

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService extends ChangeNotifier {
  static final FavoritesService instance = FavoritesService._();
  FavoritesService._();

  static const String _kFavoritesKey = 'fluxforge_audio_favorites';

  Set<String> _favorites = {};
  bool _isInitialized = false;

  /// Get all favorite file paths
  Set<String> get favorites => Set.unmodifiable(_favorites);

  /// Check if a file is favorited
  bool isFavorite(String filePath) => _favorites.contains(filePath);

  /// Initialize from SharedPreferences
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kFavoritesKey);
      if (saved != null) {
        _favorites = Set.from(saved);
      }
      _isInitialized = true;
    } catch (e) {
      _favorites = {};
      _isInitialized = true;
    }
  }

  /// Toggle favorite status for a file
  Future<void> toggleFavorite(String filePath) async {
    if (!_isInitialized) {
      await init();
    }

    if (_favorites.contains(filePath)) {
      _favorites.remove(filePath);
    } else {
      _favorites.add(filePath);
    }

    await _save();
    notifyListeners();
  }

  /// Add a file to favorites
  Future<void> addFavorite(String filePath) async {
    if (!_isInitialized) {
      await init();
    }

    if (!_favorites.contains(filePath)) {
      _favorites.add(filePath);
      await _save();
      notifyListeners();
    }
  }

  /// Remove a file from favorites
  Future<void> removeFavorite(String filePath) async {
    if (!_isInitialized) {
      await init();
    }

    if (_favorites.contains(filePath)) {
      _favorites.remove(filePath);
      await _save();
      notifyListeners();
    }
  }

  /// Clear all favorites
  Future<void> clearAll() async {
    if (!_isInitialized) {
      await init();
    }

    _favorites.clear();
    await _save();
    notifyListeners();
  }

  /// Get favorite count
  int get count => _favorites.length;

  /// Persist to SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kFavoritesKey, _favorites.toList());
    } catch (e) { /* ignored */ }
  }

  /// Filter files to show only favorites
  List<T> filterFavorites<T>(List<T> items, String Function(T) pathExtractor) {
    return items.where((item) => _favorites.contains(pathExtractor(item))).toList();
  }
}
