import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medigo/services/bdpm_importer.dart';
import 'package:medigo/services/bdpm_import_api.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/invite_service.dart';
import 'package:medigo/services/roles.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  static const String _metadataId = '00000000-0000-0000-0000-000000000001';
  int? _countDrugs;
  int? _countPresentations;
  DateTime? _lastImportedAt;
  bool _importing = false;
  double _progress = 0;
  String _step = '';

  bool _isAdmin = false;
  final TextEditingController _inviteEmailCtrl = TextEditingController();
  List<Map<String, dynamic>> _pendingInvites = const [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAdminAndInvites();
  }

  Future<void> _loadStats() async {
    try {
      final client = SupabaseConfig.client;
      final md = await client
          .from('drug_metadata')
          .select('*')
          .eq('id', _metadataId)
          .maybeSingle();
      if (md != null && mounted) {
        setState(() {
          _countDrugs = md['count_drugs'] as int?;
          _countPresentations = md['count_presentations'] as int?;
          if (md['last_imported_at'] != null) {
            _lastImportedAt = DateTime.tryParse(md['last_imported_at'] as String);
          }
        });
      }
    } catch (e) {
      debugPrint('Advanced: Failed to load stats: $e');
    }
  }

  Future<void> _loadAdminAndInvites() async {
    try {
      final isAdm = await RolesService.isAdmin();
      if (!mounted) return;
      setState(() => _isAdmin = isAdm);
      if (isAdm) await _refreshPendingInvites();
    } catch (e) {
      debugPrint('Advanced: load admin/invites failed: $e');
    }
  }

  Future<void> _refreshPendingInvites() async {
    try {
      final list = await InviteService.listPendingInvites();
      if (mounted) setState(() => _pendingInvites = list);
    } catch (e) {
      debugPrint('Advanced: refresh invites failed: $e');
    }
  }

  Future<void> _runServerImport() async {
    if (SupabaseConfig.auth.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter pour déclencher la mise à jour serveur.')));
      }
      return;
    }
    setState(() {
      _importing = true;
      _progress = 0.05;
      _step = 'Import serveur: spécialités (CIS) + présentations (CIP)...';
    });
    try {
      final r = await BdpmImportApi.runServerImportSplit();
      if (!mounted) return;
      if (!r.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec: ${r.message}')));
        return;
      }
      await _loadStats();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import serveur terminé (CIS + CIP).')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _progress = 0;
          _step = '';
        });
      }
    }
  }

  Future<void> _runLocalImport() async {
    if (SupabaseConfig.auth.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter pour importer localement.')));
      }
      return;
    }
    setState(() {
      _importing = true;
      _progress = 0;
      _step = 'Analyse et insertion locales...';
    });
    try {
      final importer = BdpmImporter();
      await importer.importAll(onProgress: (p, s) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _step = s;
        });
      });
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import local terminé.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec de l\'import local: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showPendingInvitesSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.pending, color: cs.primary),
              const SizedBox(width: 8),
              Text('Invitations en attente', style: Theme.of(ctx).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            if (_pendingInvites.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('— aucune invitation en attente —', style: Theme.of(ctx).textTheme.bodyMedium),
              )
            else
              ..._pendingInvites.map((inv) {
                final email = (inv['email'] as String?)?.trim();
                final code = inv['code'] as String? ?? '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mark_email_unread),
                  title: Text(email == null || email.isEmpty ? 'Invité (sans email)' : email, overflow: TextOverflow.ellipsis),
                  subtitle: Text(code, style: Theme.of(ctx).textTheme.labelMedium),
                  trailing: IconButton(
                    tooltip: 'Copier le code',
                    icon: Icon(Icons.copy, color: cs.primary),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié.')));
                    },
                  ),
                );
              }),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres avancés')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Database tools
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.dataset, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Base de données BDPM', style: Theme.of(context).textTheme.titleMedium),
                ]),
                const SizedBox(height: 8),
                Text('Spécialités (CIS): ${_countDrugs ?? '-'}'),
                Text('Présentations (CIP): ${_countPresentations ?? '-'}'),
                Text('Dernière mise à jour: ${_lastImportedAt != null ? _lastImportedAt!.toLocal().toString() : '-'}'),
                const SizedBox(height: 12),
                if (_importing) ...[
                  LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                  const SizedBox(height: 6),
                  Text(_step, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(onPressed: _runServerImport, icon: const Icon(Icons.cloud_sync), label: const Text('Mettre à jour (serveur)')),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(onPressed: _runLocalImport, icon: const Icon(Icons.computer), label: const Text('Import local (debug)')),
                  ),
                ],
              ]),
            ),
          ),

          const SizedBox(height: 12),

          if (_isAdmin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.sms, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text('Système d\'invitation'),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _inviteEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.email), labelText: 'Adresse email du compte (optionnel)'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final email = _inviteEmailCtrl.text.trim();
                        final code = await InviteService.createSignupInvite(email: email.isEmpty ? null : email);
                        if (code == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de créer l\'invitation.')));
                          return;
                        }
                        try { await Clipboard.setData(ClipboardData(text: code)); } catch (_) {}
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation créée: $code')));
                        await _refreshPendingInvites();
                      },
                      icon: const Icon(Icons.key),
                      label: const Text('Générer un code d\'invitation'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pendingInvites.isEmpty ? null : _showPendingInvitesSheet,
                      icon: const Icon(Icons.list),
                      label: Text('Voir les invitations en attente (${_pendingInvites.length})'),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
