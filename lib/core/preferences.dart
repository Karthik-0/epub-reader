import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

// Riverpod provider for SharedPreferences instance
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

// Riverpod provider for user's chosen font size (14, 17, or 20)
final fontSizeProvider = FutureProvider<double>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return (prefs.getDouble('font_size') ?? 17.0).clamp(14.0, 23.0);
});

// StateNotifier for reactive font size changes
class FontSizeNotifier extends StateNotifier<double> {
  final SharedPreferences prefs;

  FontSizeNotifier(this.prefs) : super(prefs.getDouble('font_size') ?? 17.0);

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(14.0, 23.0);
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

final readerFontFamilyProvider =
    AsyncNotifierProvider<ReaderFontFamilyNotifier, String>(
        ReaderFontFamilyNotifier.new);

class ReaderFontFamilyNotifier extends AsyncNotifier<String> {
  static const _key = 'reader_font_family';

  @override
  Future<String> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return prefs.getString(_key) ?? ReaderTypography.bookerly;
  }

  Future<void> setFontFamily(String fontFamily) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_key, fontFamily);
    state = AsyncData(fontFamily);
  }
}

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

final readerColorModeProvider =
    AsyncNotifierProvider<ReaderColorModeNotifier, ReaderColorMode>(
        ReaderColorModeNotifier.new);

class ReaderColorModeNotifier extends AsyncNotifier<ReaderColorMode> {
  static const _key = 'reader_color_mode';

  @override
  Future<ReaderColorMode> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final raw = prefs.getString(_key) ?? ReaderColorMode.sepia.name;
    return ReaderColorMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ReaderColorMode.sepia,
    );
  }

  Future<void> setMode(ReaderColorMode mode) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_key, mode.name);
    state = AsyncData(mode);
  }
}

enum EpubReaderEngine { flutter, readium }

final epubReaderEngineProvider =
    AsyncNotifierProvider<EpubReaderEngineNotifier, EpubReaderEngine>(
      EpubReaderEngineNotifier.new,
    );

class EpubReaderEngineNotifier extends AsyncNotifier<EpubReaderEngine> {
  static const _key = 'epub_reader_engine';

  @override
  Future<EpubReaderEngine> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final raw = prefs.getString(_key) ?? EpubReaderEngine.readium.name;
    return EpubReaderEngine.values.firstWhere(
      (engine) => engine.name == raw,
      orElse: () => EpubReaderEngine.readium,
    );
  }

  Future<void> setEngine(EpubReaderEngine engine) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_key, engine.name);
    state = AsyncData(engine);
  }
}
