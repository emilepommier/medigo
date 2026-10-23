import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/cupertino.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _packageInfo = info);
      }
    } catch (e) {
      debugPrint('Failed to load package info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final version = _packageInfo?.version ?? '1.0.0';
    final buildNumber = _packageInfo?.buildNumber ?? '1';
    final packageName = _packageInfo?.packageName ?? 'ovh.pommier.medigo';

    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // App logo centered
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  image: DecorationImage(image: AssetImage('assets/images/app_icon.png')),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // App name
            Text(
              'Medigo',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Application de gestion de pharmacie',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Version info
            _InfoItem(
              icon: Icons.info_outline,
              label: 'Version',
              value: version,
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            _InfoItem(
              icon: Icons.build_outlined,
              label: 'Numéro de build',
              value: buildNumber,
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            _InfoItem(
              icon: Icons.inventory_2_outlined,
              label: 'ID de package',
              value: packageName,
              color: cs.primary,
            ),
            const SizedBox(height: 32),

            // Description section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Description',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Medigo est une application de gestion de pharmacie qui vous aide à organiser et suivre vos médicaments de manière sécurisée. Gérez facilement votre pharmacie familiale, suivez les dates de péremption et partagez l\'accès avec votre famille.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 32),

            // Features section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fonctionnalités',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            _FeatureItem(
              icon: Icons.calendar_month,
              title: 'Gestion des médicaments',
              description:
                  'Organisez votre pharmacie et suivez les dates de péremption',
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            _FeatureItem(
              icon: Icons.qr_code_scanner,
              title: 'Scanner de codes CIP',
              description:
                  'Ajoutez rapidement des médicaments en scannant leur code',
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            _FeatureItem(
              icon: Icons.family_restroom,
              title: 'Partage familial',
              description:
                  'Partagez votre pharmacie avec les membres de votre famille',
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            _FeatureItem(
              icon: CupertinoIcons.checkmark_shield,
              title: 'Données privées',
              description: 'Vos données sont stockées de manière sécurisée',
              color: cs.primary,
            ),
            const SizedBox(height: 32),

            // Development section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Développement',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.flutter_dash, color: cs.primary, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Développé avec Flutter',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.cloud, color: cs.primary, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Alimenté par Supabase',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 48),

            // Copyright
            Center(
              child: Text(
                '© 2025 Medigo.\nTous droits réservés.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
