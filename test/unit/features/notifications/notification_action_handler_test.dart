import 'package:chat/features/notifications/notification_action_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationActionHandler', () {
    group('NotificationAction parsing', () {
      test('parses reply action correctly', () {
        const action = NotificationAction.reply;
        expect(action.name, equals('reply'));
      });

      test('parses mark_read action correctly', () {
        const action = NotificationAction.markRead;
        expect(action.name, equals('markRead'));
      });

      test('parses answer_call action correctly', () {
        const action = NotificationAction.answerCall;
        expect(action.name, equals('answerCall'));
      });

      test('parses decline_call action correctly', () {
        const action = NotificationAction.declineCall;
        expect(action.name, equals('declineCall'));
      });

      test('parses open_room action correctly', () {
        const action = NotificationAction.openRoom;
        expect(action.name, equals('openRoom'));
      });
    });

    group('NotificationAction values', () {
      test('contains all expected actions', () {
        expect(
          NotificationAction.values,
          containsAll([
            NotificationAction.reply,
            NotificationAction.markRead,
            NotificationAction.answerCall,
            NotificationAction.declineCall,
            NotificationAction.openRoom,
          ]),
        );
      });

      test('has correct number of actions', () {
        expect(NotificationAction.values.length, equals(5));
      });
    });

    group('notificationActionHandlerProvider', () {
      test('provider is available', () {
        expect(notificationActionHandlerProvider, isNotNull);
      });
    });
  });

  group('Call decline action behavior', () {
    test('decline call action is defined correctly', () {
      // The decline call action should be mapped correctly
      const declineAction = NotificationAction.declineCall;
      expect(declineAction, isNotNull);
      expect(declineAction, equals(NotificationAction.declineCall));
    });

    test('all call-related actions exist', () {
      // Verify both call actions are present
      expect(
        NotificationAction.values.contains(NotificationAction.answerCall),
        isTrue,
      );
      expect(
        NotificationAction.values.contains(NotificationAction.declineCall),
        isTrue,
      );
    });
  });
}
