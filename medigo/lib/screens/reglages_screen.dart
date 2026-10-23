import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/auth/supabase_auth_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/services/family_service.dart';
import 'package:medigo/services/roles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medigo/services/notification_service.dart';
import 'package:provider/provider.dart';
import 'package:medigo/services/family_state.dart';

class ReglagesScreen extends StatefulWidget {
  const ReglagesScreen({super.key});

  @override
  State<ReglagesScreen> createState() => _ReglagesScreenState();
}

class _ReglagesScreenState extends State<ReglagesScreen> {
  // Advanced database tools have moved to a dedicated screen
  final TextEditingController _inviteCtrl = TextEditingController();
  bool _isAdmin = false;
  bool _notifEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadNotifPref();
  }

  Future<void> _loadRole() async {
    final isAdm = await RolesService.isAdmin();
    if (mounted) {
      setState(() => _isAdmin = isAdm);
    }
  }

  Future<void> _loadNotifPref() async {
    try {
      final enabled = await NotificationService.isEnabled();
      if (mounted) setState(() => _notifEnabled = enabled);
    } catch (e) {
      debugPrint('Failed to load notif pref: $e');
    }
  }

  Future<void> _createFamily() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;
    final defaultName = 'Famille de ${user.email ?? 'utilisateur'}';
    final id = await FamilyService.createFamily(defaultName);
    if (!mounted) return;
    if (id != null) {
      await context.read<FamilyState>().refresh();
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
      await context.read<FamilyState>().refresh();
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

  Future<void> _showEditFamilyNameSheet() async {
    final cs = Theme.of(context).colorScheme;
    final famName = context.read<FamilyState>().familyName;
    final ctrl = TextEditingController(text: famName ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.edit, color: cs.primary),
                const SizedBox(width: 8),
                Text('Modifier le nom de la famille',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom de la famille',
                  prefixIcon: Icon(Icons.family_restroom),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) return;
                    final ok = await FamilyService.renameFamily(name);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    await context.read<FamilyState>().refresh();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(ok
                              ? 'Nom de la famille mis à jour.'
                              : 'Impossible de mettre à jour le nom.')),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMembersSheet() async {
    final cs = Theme.of(context).colorScheme;
    final membersSnapshot = context.read<FamilyState>().members;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.group, color: cs.primary),
                const SizedBox(width: 8),
                Text('Membres de la famille',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ]),
              const SizedBox(height: 8),
              if (membersSnapshot.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('— aucun autre membre —',
                      style: Theme.of(ctx).textTheme.bodyMedium),
                )
              else
                ...membersSnapshot.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person),
                      title: Text(m['user_id'] as String? ?? ''),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(ctx).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m['role'] as String? ?? 'member',
                            style: Theme.of(ctx).textTheme.labelSmall),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  // Database tools moved to Advanced Settings

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final famState = context.watch<FamilyState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_circle, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('Mon compte'),
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
                            const Text('Non connecté'),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user.email ?? '(no email)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _isAdmin
                                          ? Icons.shield
                                          : Icons.person_outline,
                                      color: cs.primary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isAdmin
                                          ? 'Administrateur'
                                          : 'Utilisateur standard',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('Paramètres'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alertes importantes'),
                    value: _notifEnabled,
                    onChanged: (v) async {
                      setState(() => _notifEnabled = v);
                      await NotificationService.setEnabled(v);
                      if (v) await NotificationService.requestPermissions();
                    },
                  ),
                  Text(
                    'Recevoire une alerte lorsqu’une boîte arrive à péremption',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.family_restroom, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('Ma famille'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (famState.familyId == null) ...[
                    const Text('Vous n\'êtes pas encore dans une famille.'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _createFamily,
                            icon: const Icon(Icons.create_new_folder),
                            label: const Text('Créer une famille'),
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
                              labelText: 'Rejoindre avec un code',
                              prefixIcon: Icon(Icons.vpn_key),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _redeemInvite,
                          icon: const Icon(Icons.group_add),
                          label: const Text('Rejoindre'),
                        ),
                      ],
                    ),
                  ] else ...[
                    InkWell(
                      onTap: _showEditFamilyNameSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.badge, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                famState.familyName ?? 'Nom de la famille',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.edit),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Code d\'invitation',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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
                              famState.inviteCode ?? '—',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copier',
                            onPressed: () async {
                              final code = famState.inviteCode;
                              if (code == null) return;
                              await Clipboard.setData(
                                  ClipboardData(text: code));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Alertes importantes')),
                              );
                            },
                            icon: Icon(Icons.copy, color: cs.primary),
                          ),
                          IconButton(
                            tooltip: 'Partager par SMS',
                            onPressed: () async {
                              final code = famState.inviteCode;
                              if (code == null) return;
                              final msg =
                                  'Rejoins ma famille sur l\'app: CODE $code';
                              await _shareSms(msg);
                            },
                            icon: Icon(Icons.share, color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showMembersSheet,
                        icon: const Icon(Icons.group),
                        label: Text('Voir les membres (${famState.members.length})'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.tune, color: cs.primary),
              title: const Text('Paramètres avancés'),
              subtitle: const Text(
                'Outils de base de données et système d\'invitation',
              ),
              onTap: () => context.pushNamed('advanced_settings'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.info, color: cs.primary),
              title: const Text('À propos'),
              subtitle: const Text('Informations sur l\'application'),
              onTap: () => context.pushNamed('about'),
            ),
          ),
          const SizedBox(height: 12),
          if (SupabaseConfig.auth.currentUser != null)
            Center(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await SupabaseAuthManager().signOut();
                    if (!mounted) return;
                    // FamilyState will clear itself via auth listener
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Erreur lors de la déconnexion: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ),
        ],
      ),
    );
  }
}
