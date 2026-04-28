import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Riverpod provider for SharedPreferences instance
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

// Riverpod provider for user's chosen font size (14, 17, or 20)
final fontSizeProvider = FutureProvider<double>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return (prefs.getDouble('font_size') ?? 17.0).clamp(14.0, 20.0);
});

// StateNotifier for reactive font size changes
class FontSizeNotifier extends StateNotifier<double> {
  final SharedPreferences prefs;

  FontSizeNotifier(this.prefs) : super(prefs.getDouble('font_size') ?? 17.0);

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(14.0, 20.0);
    state = clamped;
    await prefs.setDouble('font_size', clamped);
  }
}

// StateNotifierProvider for font size changes (reactive)
final fontSizeStateProvider =
    StateNotifierProvider<FontSizeNotifier, double>((ref) {
  // This won't be called initially; we need to construct with prefs.
  // Use the AsyncValue from sharedPreferencesProvider instead.
  throw UnimplementedError(
      'Use fontSizeProviderInit to properly initialize with SharedPreferences');
});

// Alternative: easier provider that gives access to both the current value and setter
final fontSizeAsync = FutureProvider<double>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return prefs.getDouble('font_size') ?? 17.0;
});

/// Helper to get or initialize font size with SharedPreferences available.
Future<FontSizeNotifier> initFontSizeNotifier() async {
  final prefs = await SharedPreferences.getInstance();
  return FontSizeNotifier(prefs);
}

// ---------------------------------------------------------------------------
// Theme mode — persisted across restarts via SharedPreferences
// ---------------------------------------------------------------------------

/// Notifier that loads/saves the dark mode flag from SharedPreferences.
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  static const _key = 'dark_mode';

  @override
  Future<ThemeMode> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final saved = prefs.getBool(_key);
    if (saved == null) return ThemeMode.system;
    return saved ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? ThemeMode.system;
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_key, next == ThemeMode.dark);
    state = AsyncData(next);
  }
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
