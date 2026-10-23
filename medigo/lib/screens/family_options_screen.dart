import 'package:flutter/material.dart';
import 'package:medigo/services/family_service.dart';

class FamilyOptionsScreen extends StatefulWidget {
  const FamilyOptionsScreen({super.key});

  @override
  State<FamilyOptionsScreen> createState() => _FamilyOptionsScreenState();
}

class _FamilyOptionsScreenState extends State<FamilyOptionsScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = true;
  String? _familyId;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fam = await FamilyService.getCurrentFamily();
    if (!mounted) return;
    setState(() {
      _familyId = fam?['id'] as String?;
      _nameCtrl.text = fam?['name'] as String? ?? '';
      _inviteCode = fam == null ? null : null;
      _loading = false;
    });
    if (_familyId != null) {
      final code = await FamilyService.getInviteCode();
      if (!mounted) return;
      setState(() => _inviteCode = code);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await FamilyService.renameFamily(_nameCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Nom de la famille mis à jour.' : 'Impossible de mettre à jour le nom.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Options de la famille')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_familyId != null) ...[
                    Text('Identifiant: $_familyId', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 12),
                    if (_inviteCode != null) ...[
                      Text('Code d\'invitation', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_inviteCode!, style: Theme.of(context).textTheme.titleLarge),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la famille',
                      prefixIcon: Icon(Icons.edit),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
