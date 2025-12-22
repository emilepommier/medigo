import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:medigo/services/bdpm_importer.dart';
import 'package:medigo/services/bdpm_import_api.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/auth/supabase_auth_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/services/family_service.dart';
import 'package:medigo/services/roles.dart';
import 'package:medigo/services/invite_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ReglagesScreen extends StatefulWidget {
  const ReglagesScreen({super.key});

  @override
  State<ReglagesScreen> createState() => _ReglagesScreenState();
}

class _ReglagesScreenState extends State<ReglagesScreen> {
  static const String _metadataId = '00000000-0000-0000-0000-000000000001';
  int? _countDrugs;
  int? _countPresentations;
  DateTime? _lastImportedAt;
  bool _importing = false;
  double _progress = 0;
  String _step = '';
  String? _familyId;
  List<Map<String, dynamic>> _members = const [];
  String? _familyInviteCode;
  final TextEditingController _inviteCtrl = TextEditingController();
  final TextEditingController _inviteEmailCtrl = TextEditingController();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadFamily();
    _loadRole();
  }

  Future<void> _loadStats() async {
    try {
      final client = SupabaseConfig.client;
      final md = await client
          .from('drug_metadata')
          .select('*')
          .eq('id', _metadataId)
          .maybeSingle() as Map<String, dynamic>?;

      if (md != null) {
        setState(() {
          _countDrugs = md['count_drugs'] as int?;
          _countPresentations = md['count_presentations'] as int?;
          if (md['last_imported_at'] != null) {
            _lastImportedAt =
                DateTime.tryParse(md['last_imported_at'] as String);
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load stats: $e');
    }
  }

  Future<void> _loadFamily() async {
    try {
      if (SupabaseConfig.auth.currentUser == null) return;
      final famId = await FamilyService.getCurrentFamilyId();
      final members = await FamilyService.getMembers();
      final inviteCode = await FamilyService.getInviteCode();
      if (!mounted) return;
      setState(() {
        _familyId = famId;
        _members = members;
        _familyInviteCode = inviteCode;
      });
    } catch (e) {
      debugPrint('Failed to load family: $e');
    }
  }

  Future<void> _loadRole() async {
    final isAdm = await RolesService.isAdmin();
    if (mounted) {
      setState(() => _isAdmin = isAdm);
    }
  }

  Future<void> _createFamily() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;
    final defaultName = 'Famille de ${user.email ?? 'utilisateur'}';
    final id = await FamilyService.createFamily(defaultName);
    if (!mounted) return;
    if (id != null) {
      await _loadFamily();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Famille créée.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de la création de la famille')),
      );
    }
  }

  Future<void> _redeemInvite() async {
    final code = _inviteCtrl.text.trim();
    if (code.isEmpty) return;
    final ok = await FamilyService.redeemInvite(code);
    if (!mounted) return;
    if (ok) {
      _inviteCtrl.clear();
      await _loadFamily();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous avez rejoint la famille.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code invalide ou expiré.')),
      );
    }
  }

  Future<void> _shareSms(String body) async {
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(body)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Impossible d\'ouvrir l\'application SMS. Code copié.')),
      );
    }
  }

  Future<void> _runServerImport() async {
    // Exige l'authentification pour le déclenchement manuel
    if (SupabaseConfig.auth.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Veuillez vous connecter pour déclencher la mise à jour serveur.')),
        );
        // Redirige vers l'écran de connexion
        context.push('/login');
      }
      return;
    }
    setState(() {
      _importing = true;
      _progress = 0.05;
      _step = 'Import serveur: spécialités (CIS) + présentations (CIP)...';
    });
    try {
      // Import scindé (CIS puis CIP en chunks) pour robustesse et éviter les 504
      final r = await BdpmImportApi.runServerImportSplit();
      if (!mounted) return;
      if (!r.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec: ${r.message}')),
        );
        return;
      }

      await _loadStats();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import serveur terminé (CIS + CIP).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
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
    // Import local de secours (utilise les fichiers embarqués et subit les RLS)
    if (SupabaseConfig.auth.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Veuillez vous connecter pour importer localement.')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import local terminé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l\'import local: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          // Account card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.account_circle, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Account'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final user = SupabaseConfig.auth.currentUser;
                      if (user == null) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Not signed in'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => context.push('/login'),
                                  icon: const Icon(Icons.login),
                                  label: const Text('Se connecter'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => context.push('/signup'),
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('Créer un compte'),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.email ?? '(no email)'),
                          if (_isAdmin) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                shape: BoxShape.rectangle,
                              ),
                              child: Row(children: const [
                                Icon(Icons.shield, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Administrator')
                              ]),
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await SupabaseAuthManager().signOut();
                                if (!mounted) return;
                                setState(() {
                                  _familyId = null;
                                  _members = const [];
                                  _familyInviteCode = null;
                                });
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Erreur lors de la déconnexion: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('Se déconnecter'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Family section styled like screenshot
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.family_restroom, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Family'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_familyId == null) ...[
                    Text('You are not in a family yet.'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _createFamily,
                            icon: const Icon(Icons.create_new_folder),
                            label: const Text('Create Family'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inviteCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Join with code',
                              prefixIcon: Icon(Icons.vpn_key),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _redeemInvite,
                          icon: const Icon(Icons.group_add),
                          label: const Text('Join'),
                        ),
                      ],
                    ),
                  ] else ...[
                    InkWell(
                      onTap: () => context.push('/settings/family'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.group, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(child: Text('Family options')),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Invite Code',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _familyInviteCode ?? '—',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copier',
                            onPressed: () async {
                              final code = _familyInviteCode;
                              if (code == null) return;
                              await Clipboard.setData(
                                  ClipboardData(text: code));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copié.')),
                              );
                            },
                            icon: const Icon(Icons.copy, color: Colors.blue),
                          ),
                          IconButton(
                            tooltip: 'Partager par SMS',
                            onPressed: () async {
                              final code = _familyInviteCode;
                              if (code == null) return;
                              final msg =
                                  'Rejoins ma famille sur l\'app: CODE $code';
                              await _shareSms(msg);
                            },
                            icon: const Icon(Icons.share, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Members',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    ...(_members.isEmpty
                        ? [const Text('— aucun autre membre —')]
                        : _members
                            .map((m) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              m['user_id'] as String? ?? '')),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                            m['role'] as String? ?? 'member',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                      )
                                    ],
                                  ),
                                ))
                            .toList()),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isAdmin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.sms, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Invitations (administrateur)'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inviteEmailCtrl,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.email),
                        labelText: "Adresse email du compte",
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final email = _inviteEmailCtrl.text.trim();
                          final code = await InviteService.createSignupInvite(
                              email: email.isEmpty ? null : email);
                          if (code == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Impossible de créer l\'invitation.')),
                            );
                            return;
                          }
                          final message =
                              'Inscris-toi à l\'appli : https://app.example\nCode d\'invitation: $code';
                          await _shareSms(message);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Invitation générée: $code')),
                          );
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('Envoyer une invitation par SMS'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dataset, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Base de données BDPM',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Spécialités (CIS): ${_countDrugs ?? '-'}'),
                  Text('Présentations (CIP): ${_countPresentations ?? '-'}'),
                  Text(
                      'Dernière mise à jour: ${_lastImportedAt != null ? _lastImportedAt!.toLocal().toString() : '-'}'),
                  const SizedBox(height: 12),
                  if (_importing) ...[
                    LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress),
                    const SizedBox(height: 6),
                    Text(_step,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _runServerImport,
                        icon: const Icon(Icons.cloud_sync),
                        label: const Text('Mettre à jour (serveur)'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _runLocalImport,
                        icon: const Icon(Icons.computer),
                        label: const Text('Import local (debug)'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
