import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final contactServiceProvider = Provider<ContactService>((ref) {
  return ContactService();
});

final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final service = ref.watch(contactServiceProvider);
  return service.getContacts();
});

class ContactService {
  Future<List<Contact>> getContacts() async {
    if (await FlutterContacts.requestPermission()) {
      return await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );
    }
    return [];
  }

  // TODO: Implement sync with backend to find which contacts are on the app
  // Future<List<User>> syncContacts(List<Contact> contacts) async { ... }
}
