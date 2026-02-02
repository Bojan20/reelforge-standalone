import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/comping_service.dart';
import 'package:flutter_ui/models/comping_models.dart';

void main() {
  group('CompingService', () {
    late CompingService service;

    setUp(() {
      service = CompingService.instance;
      // Clear any existing states
      for (final trackId in ['track-1', 'track-2', 'track-test']) {
        service.removeCompState(trackId);
      }
    });

    group('CompSelection', () {
      test('calculates duration correctly', () {
        const selection = CompSelection(
          trackId: 'track-1',
          takeId: 'take-1',
          startTime: 1.0,
          endTime: 5.0,
        );
        expect(selection.duration, equals(4.0));
      });

      test('converts to CompRegion', () {
        const selection = CompSelection(
          trackId: 'track-1',
          takeId: 'take-1',
          startTime: 2.0,
          endTime: 6.0,
        );
        final region = selection.toRegion();
        expect(region.trackId, equals('track-1'));
        expect(region.takeId, equals('take-1'));
        expect(region.startTime, equals(2.0));
        expect(region.endTime, equals(6.0));
        expect(region.id, isNotEmpty);
      });
    });

    group('CrossfadeInfo', () {
      test('stores crossfade information', () {
        const info = CrossfadeInfo(
          regionAId: 'region-a',
          regionBId: 'region-b',
          startTime: 5.0,
          duration: 0.1,
          curveType: CompCrossfadeType.equalPower,
        );
        expect(info.startTime, equals(5.0));
        expect(info.duration, equals(0.1));
        expect(info.curveType, equals(CompCrossfadeType.equalPower));
      });
    });

    group('Comp state management', () {
      test('initializeComp creates new state', () {
        final state = service.initializeComp('track-test');
        expect(state.trackId, equals('track-test'));
        expect(state.lanes, isNotEmpty); // Should have one lane by default
      });

      test('initializeComp returns existing state', () {
        final state1 = service.initializeComp('track-test');
        final state2 = service.initializeComp('track-test');
        expect(identical(state1, state2), isTrue);
      });

      test('getCompState returns null for unknown track', () {
        expect(service.getCompState('nonexistent'), isNull);
      });

      test('updateCompState updates state', () {
        service.initializeComp('track-test');
        final newState = CompState(trackId: 'track-test', mode: CompMode.comp);
        service.updateCompState('track-test', newState);
        expect(service.getCompState('track-test')?.mode, equals(CompMode.comp));
      });

      test('removeCompState removes state', () {
        service.initializeComp('track-test');
        service.removeCompState('track-test');
        expect(service.getCompState('track-test'), isNull);
      });
    });

    group('Lane operations', () {
      test('createLane adds new lane', () {
        service.initializeComp('track-test');
        final lane = service.createLane('track-test', name: 'My Lane');
        expect(lane, isNotNull);
        expect(lane!.name, equals('My Lane'));
      });

      test('deleteLane removes lane', () {
        service.initializeComp('track-test');
        final lane = service.createLane('track-test');
        final laneId = lane!.id;
        final success = service.deleteLane('track-test', laneId);
        expect(success, isTrue);
      });

      test('setActiveLane changes active lane', () {
        service.initializeComp('track-test');
        service.createLane('track-test');
        service.setActiveLane('track-test', 1);
        final state = service.getCompState('track-test');
        expect(state?.activeLaneIndex, equals(1));
      });

      test('toggleLanesExpanded toggles state', () {
        service.initializeComp('track-test');
        expect(service.getCompState('track-test')?.lanesExpanded, isFalse);
        service.toggleLanesExpanded('track-test');
        expect(service.getCompState('track-test')?.lanesExpanded, isTrue);
      });
    });

    group('Take operations', () {
      test('addTake adds take to lane', () {
        service.initializeComp('track-test');
        final take = Take(
          id: 'take-1',
          laneId: 'lane-0',
          trackId: 'track-test',
          takeNumber: 1,
          startTime: 0,
          duration: 5.0,
          sourcePath: '/audio/take1.wav',
          sourceDuration: 5.0,
          recordedAt: DateTime.now(),
        );
        final result = service.addTake('track-test', take);
        expect(result, isNotNull);
      });

      test('setTakeRating updates rating', () {
        service.initializeComp('track-test');
        final take = Take(
          id: 'take-1',
          laneId: 'lane-0',
          trackId: 'track-test',
          takeNumber: 1,
          startTime: 0,
          duration: 5.0,
          sourcePath: '/audio/take1.wav',
          sourceDuration: 5.0,
          recordedAt: DateTime.now(),
        );
        service.addTake('track-test', take);
        service.setTakeRating('track-test', 'take-1', TakeRating.best);
        final foundTake = service.getTake('track-test', 'take-1');
        expect(foundTake?.rating, equals(TakeRating.best));
      });
    });

    group('Selection operations', () {
      test('startSelection creates pending selection', () {
        service.startSelection('track-1', 'take-1', 2.0);
        expect(service.pendingSelection, isNotNull);
        expect(service.pendingSelection?.startTime, equals(2.0));
      });

      test('updateSelection updates end time', () {
        service.startSelection('track-1', 'take-1', 2.0);
        service.updateSelection(5.0);
        expect(service.pendingSelection?.endTime, equals(5.0));
      });

      test('cancelSelection clears pending selection', () {
        service.startSelection('track-1', 'take-1', 2.0);
        service.cancelSelection();
        expect(service.pendingSelection, isNull);
      });

      test('commitSelection returns null for short selections', () {
        service.startSelection('track-1', 'take-1', 2.0);
        service.updateSelection(2.005); // Too short
        final region = service.commitSelection();
        expect(region, isNull);
      });
    });

    group('Crossfade utilities', () {
      test('linear crossfade curve', () {
        expect(CompingService.applyCrossfadeCurve(0.0, CompCrossfadeType.linear), equals(0.0));
        expect(CompingService.applyCrossfadeCurve(0.5, CompCrossfadeType.linear), equals(0.5));
        expect(CompingService.applyCrossfadeCurve(1.0, CompCrossfadeType.linear), equals(1.0));
      });

      test('equal power crossfade curve', () {
        expect(CompingService.applyCrossfadeCurve(0.0, CompCrossfadeType.equalPower), equals(0.0));
        expect(
          CompingService.applyCrossfadeCurve(0.5, CompCrossfadeType.equalPower),
          closeTo(0.707, 0.01),
        );
        expect(CompingService.applyCrossfadeCurve(1.0, CompCrossfadeType.equalPower), equals(1.0));
      });

      test('getCrossfadeGains returns correct values', () {
        // Before crossfade
        var (gainA, gainB) = CompingService.getCrossfadeGains(4.0, 5.0, 6.0, CompCrossfadeType.linear);
        expect(gainA, equals(1.0));
        expect(gainB, equals(0.0));

        // After crossfade
        (gainA, gainB) = CompingService.getCrossfadeGains(7.0, 5.0, 6.0, CompCrossfadeType.linear);
        expect(gainA, equals(0.0));
        expect(gainB, equals(1.0));

        // Mid-crossfade (linear)
        (gainA, gainB) = CompingService.getCrossfadeGains(5.5, 5.0, 6.0, CompCrossfadeType.linear);
        expect(gainA, equals(0.5));
        expect(gainB, equals(0.5));
      });
    });

    group('Service settings', () {
      test('setSelectionTool updates tool', () {
        service.setSelectionTool(CompSelectionTool.razor);
        expect(service.selectionTool, equals(CompSelectionTool.razor));
      });

      test('setDefaultCrossfade clamps value', () {
        service.setDefaultCrossfade(2.0);
        expect(service.defaultCrossfade, equals(1.0)); // Clamped to max
        service.setDefaultCrossfade(-1.0);
        expect(service.defaultCrossfade, equals(0.001)); // Clamped to min
      });

      test('setDefaultCrossfadeType updates type', () {
        service.setDefaultCrossfadeType(CompCrossfadeType.sCurve);
        expect(service.defaultCrossfadeType, equals(CompCrossfadeType.sCurve));
      });
    });
  });
}
