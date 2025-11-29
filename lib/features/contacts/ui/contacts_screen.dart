import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/contact_service.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: contactsAsync.when(
        data: (contacts) {
          if (contacts.isEmpty) {
            return const Center(
              child: Text('No contacts found or permission denied'),
            );
          }
          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(
                leading: (contact.photo != null)
                    ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
                    : CircleAvatar(child: Text(contact.displayName[0])),
                title: Text(contact.displayName),
                subtitle: contact.phones.isNotEmpty
                    ? Text(contact.phones.first.number)
                    : null,
                onTap: () {
                  // TODO: Start chat with this contact
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
