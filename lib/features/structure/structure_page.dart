import 'package:flutter/material.dart';

import '../contacts/contacts_page.dart';

class StructurePage extends StatelessWidget {
  const StructurePage({super.key});

  @override
  Widget build(BuildContext context) {
    // В HomeShell уже есть общий Scaffold + AppBar
    return const ContactsPage();
  }
}
