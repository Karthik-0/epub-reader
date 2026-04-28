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
