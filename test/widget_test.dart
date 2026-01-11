import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chat/main.dart';
import 'package:chat/features/messages/ui/chat_input_bar.dart';

void main() {
  testWidgets('Chat input bar smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    // Wait for app to load
    await tester.pumpAndSettle();

    // The app should load without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Chat input bar widget test', (WidgetTester tester) async {
    // Build just the chat input bar widget
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatInputBar(roomId: 'test-room-123', roomName: 'Test Room'),
          ),
        ),
      ),
    );

    // Verify input bar components exist
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    // Test typing in text field
    await tester.enterText(find.byType(TextField), 'Hello world');
    await tester.pump();

    // Verify mic button changes to send button when text is entered
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);

    // Test sending message
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    // Verify text field is cleared after sending
    expect(find.text('Hello world'), findsNothing);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);
  });

  testWidgets('Chat input bar attachment options', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatInputBar(roomId: 'test-room-456', roomName: 'Test Room'),
          ),
        ),
      ),
    );

    // Tap attachment button
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    // Verify attachment options appear
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);

    // Close the modal
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
  });

  testWidgets('Chat input bar voice recording toggle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatInputBar(roomId: 'test-room-789', roomName: 'Test Room'),
          ),
        ),
      ),
    );

    // Verify mic button is visible initially
    expect(find.byIcon(Icons.mic), findsOneWidget);

    // Tap mic button to start recording
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();

    // Verify stop button appears during recording
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);

    // Tap stop button to end recording
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    // Verify mic button returns after stopping
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });
}
