import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/startup/startup_service.dart';

void main() {
  group('StartupPhase', () {
    test('has all expected phases', () {
      expect(StartupPhase.values, contains(StartupPhase.critical));
      expect(StartupPhase.values, contains(StartupPhase.essential));
      expect(StartupPhase.values, contains(StartupPhase.deferred));
    });

    test('phases are in correct order', () {
      expect(StartupPhase.values.length, equals(3));
      expect(StartupPhase.values[0], equals(StartupPhase.critical));
      expect(StartupPhase.values[1], equals(StartupPhase.essential));
      expect(StartupPhase.values[2], equals(StartupPhase.deferred));
    });
  });

  group('StartupState', () {
    test('has all expected states', () {
      expect(StartupState.values, contains(StartupState.initial));
      expect(StartupState.values, contains(StartupState.initializingCritical));
      expect(StartupState.values, contains(StartupState.initializingEssential));
      expect(StartupState.values, contains(StartupState.interactive));
      expect(StartupState.values, contains(StartupState.complete));
      expect(StartupState.values, contains(StartupState.error));
    });

    test('states are in correct order', () {
      expect(StartupState.values.length, equals(6));
    });
  });

  group('StartupProgress', () {
    test('default state is initial', () {
      const progress = StartupProgress(state: StartupState.initial);
      expect(progress.state, equals(StartupState.initial));
      expect(progress.currentTask, isNull);
      expect(progress.progress, equals(0.0));
      expect(progress.errorMessage, isNull);
    });

    test('copyWith creates new instance with updated values', () {
      const progress = StartupProgress(
        state: StartupState.initial,
        currentTask: 'Task 1',
        progress: 0.5,
      );

      final updated = progress.copyWith(
        state: StartupState.interactive,
        currentTask: 'Task 2',
        progress: 0.8,
      );

      expect(updated.state, equals(StartupState.interactive));
      expect(updated.currentTask, equals('Task 2'));
      expect(updated.progress, equals(0.8));
    });

    test('copyWith preserves unchanged values', () {
      const progress = StartupProgress(
        state: StartupState.initial,
        currentTask: 'Task 1',
        progress: 0.5,
      );

      final updated = progress.copyWith(state: StartupState.interactive);

      expect(updated.state, equals(StartupState.interactive));
      expect(updated.currentTask, equals('Task 1'));
      expect(updated.progress, equals(0.5));
    });

    test('isComplete returns true only when complete', () {
      expect(
        const StartupProgress(state: StartupState.initial).isComplete,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.initializingCritical)
            .isComplete,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.interactive).isComplete,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.complete).isComplete,
        isTrue,
      );
      expect(
        const StartupProgress(state: StartupState.error).isComplete,
        isFalse,
      );
    });

    test('isInteractive returns true for interactive and complete states', () {
      expect(
        const StartupProgress(state: StartupState.initial).isInteractive,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.initializingCritical)
            .isInteractive,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.initializingEssential)
            .isInteractive,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.interactive).isInteractive,
        isTrue,
      );
      expect(
        const StartupProgress(state: StartupState.complete).isInteractive,
        isTrue,
      );
      expect(
        const StartupProgress(state: StartupState.error).isInteractive,
        isFalse,
      );
    });

    test('hasError returns true only for error state', () {
      expect(
        const StartupProgress(state: StartupState.initial).hasError,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.complete).hasError,
        isFalse,
      );
      expect(
        const StartupProgress(state: StartupState.error).hasError,
        isTrue,
      );
    });

    test('error state can contain error message', () {
      const progress = StartupProgress(
        state: StartupState.error,
        errorMessage: 'Something went wrong',
      );

      expect(progress.hasError, isTrue);
      expect(progress.errorMessage, equals('Something went wrong'));
    });

    test('progress value can range from 0 to 1', () {
      const progress0 = StartupProgress(
        state: StartupState.initial,
        progress: 0.0,
      );
      const progress50 = StartupProgress(
        state: StartupState.initializingEssential,
        progress: 0.5,
      );
      const progress100 = StartupProgress(
        state: StartupState.complete,
        progress: 1.0,
      );

      expect(progress0.progress, equals(0.0));
      expect(progress50.progress, equals(0.5));
      expect(progress100.progress, equals(1.0));
    });
  });

  group('StartupProgress state transitions', () {
    test('typical successful startup sequence', () {
      // Initial state
      var progress = const StartupProgress(state: StartupState.initial);
      expect(progress.isInteractive, isFalse);
      expect(progress.isComplete, isFalse);

      // Critical initialization
      progress = progress.copyWith(
        state: StartupState.initializingCritical,
        currentTask: 'Initializing core services...',
        progress: 0.1,
      );
      expect(progress.isInteractive, isFalse);
      expect(progress.isComplete, isFalse);

      // Essential initialization
      progress = progress.copyWith(
        state: StartupState.initializingEssential,
        currentTask: 'Loading user data...',
        progress: 0.4,
      );
      expect(progress.isInteractive, isFalse);
      expect(progress.isComplete, isFalse);

      // Interactive
      progress = progress.copyWith(
        state: StartupState.interactive,
        currentTask: 'Finishing setup...',
        progress: 0.8,
      );
      expect(progress.isInteractive, isTrue);
      expect(progress.isComplete, isFalse);

      // Complete
      progress = progress.copyWith(
        state: StartupState.complete,
        currentTask: null,
        progress: 1.0,
      );
      expect(progress.isInteractive, isTrue);
      expect(progress.isComplete, isTrue);
    });

    test('error during initialization', () {
      var progress = const StartupProgress(state: StartupState.initial);

      progress = progress.copyWith(
        state: StartupState.initializingCritical,
        currentTask: 'Initializing...',
        progress: 0.1,
      );

      progress = progress.copyWith(
        state: StartupState.error,
        errorMessage: 'Firebase initialization failed',
      );

      expect(progress.hasError, isTrue);
      expect(progress.isInteractive, isFalse);
      expect(progress.isComplete, isFalse);
      expect(progress.errorMessage, contains('Firebase'));
    });
  });
}
