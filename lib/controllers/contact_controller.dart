import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact_model.dart';

class ContactController {
  static const String _storageKey = 'emergency_contacts';

  static Future<List<ContactModel>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? contactsJson = prefs.getStringList(_storageKey);

    if (contactsJson == null) return [];

    return contactsJson
        .map((json) => ContactModel.fromJson(json))
        .toList();
  }

  static Future<void> addContact(ContactModel contact) async {
    final prefs = await SharedPreferences.getInstance();
    final List<ContactModel> currentContacts = await getContacts();

    // Check if contact already exists
    if (currentContacts.any((c) => c.phoneNumber == contact.phoneNumber)) {
      return;
    }

    currentContacts.add(contact);
    final List<String> updatedJson = currentContacts
        .map((c) => c.toJson())
        .toList();

    await prefs.setStringList(_storageKey, updatedJson);
  }

  static Future<void> removeContact(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final List<ContactModel> currentContacts = await getContacts();

    currentContacts.removeWhere((c) => c.phoneNumber == phoneNumber);

    final List<String> updatedJson = currentContacts
        .map((c) => c.toJson())
        .toList();

    await prefs.setStringList(_storageKey, updatedJson);
  }
}
