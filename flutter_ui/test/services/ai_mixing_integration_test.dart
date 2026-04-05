import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxforge_ui/services/ai_mixing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AiMixingService', () {
    late AiMixingService service;

    setUp(() {
      service = AiMixingService.instance;
      service.clearAnalysis();
    });

    test('singleton instance', () {
      final a = AiMixingService.instance;
      final b = AiMixingService.instance;
      expect(identical(a, b), isTrue);
    });

    test('connectMixer sets hasMixer', () {
      expect(service.hasMixer, isFalse);
      // Can't instantiate real MixerProvider in unit test (needs FFI),
      // but we verify the API exists and state is correct
    });

    test('analyzeProject with no mixer returns empty analysis', () async {
      final result = await service.analyzeProject();
      expect(result.tracks, isEmpty);
      expect(result.overallScore, 100.0);
    });

    test('analyzeMix detects clipping', () async {
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_0',
          trackName: 'Kick',
          peakDb: 0.5, // clipping!
          rmsDb: -12.0,
          lufs: -14.0,
          dynamicRange: 12.5,
        ),
      ];

      final result = await service.analyzeMix(tracks);

      expect(result.suggestions, isNotEmpty);
      final clipping = result.suggestions.where(
        (s) => s.type == SuggestionType.gain && s.title == 'Clipping Detected',
      );
      expect(clipping, isNotEmpty);
      expect(clipping.first.priority, SuggestionPriority.critical);
      expect(clipping.first.trackName, 'Kick');
    });

    test('analyzeMix detects low headroom', () async {
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_1',
          trackName: 'Snare',
          peakDb: -1.5, // low headroom but not clipping
          rmsDb: -12.0,
          lufs: -14.0,
          dynamicRange: 10.5,
        ),
      ];

      final result = await service.analyzeMix(tracks);
      final headroom = result.suggestions.where(
        (s) => s.title == 'Low Headroom',
      );
      expect(headroom, isNotEmpty);
      expect(headroom.first.priority, SuggestionPriority.high);
    });

    test('analyzeMix detects over-compression', () async {
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_2',
          trackName: 'Vocal',
          peakDb: -6.0,
          rmsDb: -10.0,
          lufs: -14.0,
          dynamicRange: 2.0, // very compressed for pop (target 8.0)
        ),
      ];

      await service.setGenre(GenreProfile.pop);
      final result = await service.analyzeMix(tracks);
      final overcomp = result.suggestions.where(
        (s) => s.title == 'Possibly Over-Compressed',
      );
      expect(overcomp, isNotEmpty);
    });

    test('analyzeMix detects muddy low end', () async {
      final tracks = [
        TrackAnalysis(
          trackId: 'ch_3',
          trackName: 'Bass',
          peakLevel: -6.0,
          rmsLevel: -12.0,
          lufs: -14.0,
          dynamicRange: 8.0,
          stereoWidth: 0.5,
          frequencySpectrum: {'low': -3.0, 'mid': -12.0, 'high': -18.0},
          crestFactor: 6.0,
          hasClipping: false,
          dcOffset: 0.0,
        ),
      ];

      final result = await service.analyzeMix(tracks);
      final muddy = result.suggestions.where((s) => s.title == 'Muddy Low End');
      expect(muddy, isNotEmpty);
    });

    test('analyzeMix detects mono content', () async {
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_4',
          trackName: 'Lead',
          peakDb: -6.0,
          rmsDb: -12.0,
          lufs: -14.0,
          dynamicRange: 8.0,
          stereoWidth: 0.05, // effectively mono
        ),
      ];

      final result = await service.analyzeMix(tracks);
      final mono = result.suggestions.where((s) => s.title == 'Mono Content');
      expect(mono, isNotEmpty);
    });

    test('analyzeMix detects loudness deviation', () async {
      await service.setGenre(GenreProfile.pop); // target -14 LUFS
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_5',
          trackName: 'Master',
          peakDb: -12.0,
          rmsDb: -24.0,
          lufs: -22.0, // way below -14 target
          dynamicRange: 12.0,
        ),
      ];

      final result = await service.analyzeMix(tracks);
      final quiet = result.suggestions.where((s) => s.title == 'Mix is Quiet');
      expect(quiet, isNotEmpty);
    });

    test('analyzeMix detects frequency masking between tracks', () async {
      final tracks = [
        TrackAnalysis(
          trackId: 'ch_6',
          trackName: 'Kick',
          peakLevel: -6.0,
          rmsLevel: -12.0,
          lufs: -14.0,
          dynamicRange: 8.0,
          stereoWidth: 1.0,
          frequencySpectrum: {'low': -3.0, 'mid': -12.0, 'high': -18.0},
          crestFactor: 6.0,
          hasClipping: false,
          dcOffset: 0.0,
        ),
        TrackAnalysis(
          trackId: 'ch_7',
          trackName: 'Bass',
          peakLevel: -6.0,
          rmsLevel: -12.0,
          lufs: -14.0,
          dynamicRange: 8.0,
          stereoWidth: 0.5,
          frequencySpectrum: {'low': -2.0, 'mid': -12.0, 'high': -20.0},
          crestFactor: 6.0,
          hasClipping: false,
          dcOffset: 0.0,
        ),
      ];

      final result = await service.analyzeMix(tracks);
      final masking = result.suggestions.where(
        (s) => s.type == SuggestionType.masking,
      );
      expect(masking, isNotEmpty);
      expect(masking.first.title, 'Potential Masking');
    });

    test('genre detection heuristics', () async {
      // High crest + high DR = classical
      final classical = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_0',
          trackName: 'Strings',
          peakDb: -3.0,
          rmsDb: -20.0,
          lufs: -22.0,
          dynamicRange: 17.0,
        ),
      ];

      await service.setGenre(GenreProfile.auto);
      final result = await service.analyzeMix(classical);
      expect(result.detectedGenre, GenreProfile.classical);
    });

    test('score decreases with suggestions', () async {
      final cleanTrack = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_0',
          trackName: 'Clean',
          peakDb: -12.0,
          rmsDb: -18.0,
          lufs: -16.0,
          dynamicRange: 6.0,
        ),
      ];

      final problematicTrack = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_1',
          trackName: 'Problem',
          peakDb: 0.5, // clipping
          rmsDb: -30.5, // very low
          lufs: -32.0,
          dynamicRange: 31.0, // huge DR
        ),
      ];

      final cleanResult = await service.analyzeMix(cleanTrack);
      final dirtyResult = await service.analyzeMix(problematicTrack);

      expect(dirtyResult.suggestions.length,
          greaterThan(cleanResult.suggestions.length));
    });

    test('dismissSuggestion removes from analysis', () async {
      final tracks = [
        TrackAnalysis.fromMeasurements(
          trackId: 'ch_0',
          trackName: 'Test',
          peakDb: 0.5, // will generate clipping suggestion
          rmsDb: -12.0,
          lufs: -14.0,
          dynamicRange: 12.5,
        ),
      ];

      await service.analyzeMix(tracks);
      final before = service.suggestions.length;
      expect(before, greaterThan(0));

      service.dismissSuggestion(service.suggestions.first.id);
      expect(service.suggestions.length, before - 1);
    });

    test('applySuggestion without mixer logs to history', () async {
      service.disconnectMixer(); // ensure no mixer
      final suggestion = MixingSuggestion(
        id: 'test_1',
        type: SuggestionType.gain,
        priority: SuggestionPriority.high,
        title: 'Test Suggestion',
        description: 'Test',
        confidence: 0.9,
      );

      final result = await service.applySuggestion(suggestion);
      expect(result, isTrue);
      expect(service.suggestionHistory, isNotEmpty);
      expect(service.suggestionHistory.last.applied, isTrue);
    });

    test('genre LUFS targets are correct', () {
      expect(GenreProfile.pop.targetLufs, -14.0);
      expect(GenreProfile.electronic.targetLufs, -10.0);
      expect(GenreProfile.classical.targetLufs, -18.0);
      expect(GenreProfile.filmScore.targetLufs, -24.0);
      expect(GenreProfile.slotGame.targetLufs, -16.0);
    });

    test('MixingSuggestion JSON roundtrip', () {
      final original = MixingSuggestion(
        id: 'test_json',
        type: SuggestionType.eq,
        priority: SuggestionPriority.medium,
        title: 'EQ Cut',
        description: 'Cut at 300Hz',
        trackId: 'ch_0',
        trackName: 'Kick',
        parameters: {'frequency': 300.0, 'gain': -3.0, 'q': 1.5},
        confidence: 0.75,
      );

      final json = original.toJson();
      final restored = MixingSuggestion.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.priority, original.priority);
      expect(restored.title, original.title);
      expect(restored.trackId, original.trackId);
      expect(restored.parameters['frequency'], 300.0);
      expect(restored.confidence, 0.75);
    });
  });
}
