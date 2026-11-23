import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import 'theme.dart';
import 'widgets.dart';

/// Device-level preferences a member of staff may own, and one only an
/// administrator may change: whether the in-app guidance is shown at all.
class AppSettings {
  AppSettings._();

  static const _guidanceKey = 'lamaliva.guidance.on';
  static const _languageKey = 'lamaliva.language';

  static final ValueNotifier<bool> guidance = ValueNotifier<bool>(true);
  static final ValueNotifier<String> language = ValueNotifier<String>('en');

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    guidance.value = prefs.getBool(_guidanceKey) ?? true;
    language.value = prefs.getString(_languageKey) ?? 'en';
  }

  static Future<void> setGuidance(bool on) async {
    guidance.value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guidanceKey, on);
  }

  static Future<void> setLanguage(String code) async {
    language.value = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  /// Forget this device's local state — caches, held work and saved offline
  /// sign-in. The hotel's records on the server are never touched, which is
  /// why the admin screen asks twice before calling this.
  static Future<void> resetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    guidance.value = true;
    language.value = 'en';
  }
}

bool get isFrench => AppSettings.language.value == 'fr';

/// One line of instruction, written for a receptionist in Buea rather than a
/// software manual: what to do, and what it changes.
class GuideStep {
  const GuideStep(this.title, this.body, this.icon);

  final String title;
  final String body;
  final IconData icon;
}

List<GuideStep> guideFor(String role) {
  final fr = isFrench;
  final common = <GuideStep>[
    GuideStep(
      fr ? 'Commencez par Aujourd’hui' : 'Start with Today',
      fr
          ? 'Aujourd’hui montre les arrivées, les départs et les chambres à nettoyer. '
                'C’est le premier écran de chaque service.'
          : 'Today shows arrivals, departures and the rooms waiting to be cleaned. '
                'It is the first screen of every shift.',
      Icons.dashboard_outlined,
    ),
    GuideStep(
      fr ? 'Enregistrez un client' : 'Register a guest',
      fr
          ? 'Appuyez sur « Enregistrer un client », choisissez la chambre, puis le nombre '
                'de nuits. Le serveur marque la chambre occupée en même temps.'
          : 'Tap Register guest, pick the room, then the number of nights. The server '
                'marks the room occupied at the same moment.',
      Icons.person_add_alt,
    ),
    GuideStep(
      fr ? 'Prenez l’argent au bon endroit' : 'Take money in the right place',
      fr
          ? 'Un paiement de chambre se fait dans le séjour. Une boisson ou un plat vendu '
                'se fait dans la Boutique, pour que le stock et la caisse restent d’accord.'
          : 'A room payment is taken inside the stay. A drink or plate sold is taken in '
                'the Shop, so the shelf and the till always agree.',
      Icons.payments_outlined,
    ),
  ];

  switch (role) {
    case 'housekeeping':
      return [
        GuideStep(
          fr ? 'Chambres à nettoyer' : 'Rooms to clean',
          fr
              ? 'Ouvrez Chambres, trouvez la chambre marquée « nettoyage », faites le '
                    'travail, puis appuyez sur « Marquer nettoyée ». Elle redevient '
                    'disponible pour la réception.'
              : 'Open Rooms, find the room marked cleaning, do the work, then tap Mark '
                    'cleaned. It goes straight back into the free pool for reception.',
          Icons.cleaning_services_outlined,
        ),
        ...common.take(1),
      ];
    case 'inventory':
      return [
        GuideStep(
          fr ? 'Bougez le stock, ne le devinez pas' : 'Move stock, never guess',
          fr
              ? 'Utilisez « Ajouter » pour une livraison, « Retirer » pour une casse, et '
                    '« Inventaire » pour un comptage. Chaque mouvement reste dans l’historique.'
              : 'Use Add stock for a delivery, Take stock for breakage, and Stock take '
                    'for a count. Every movement stays in the history.',
          Icons.inventory_2_outlined,
        ),
        ...common.take(1),
      ];
    default:
      return common;
  }
}

/// A short, dismissible-feeling card that teaches the next useful action.
/// It is on only while an administrator leaves guidance switched on.
class GuidanceCard extends StatelessWidget {
  const GuidanceCard({super.key, required this.role, this.onOpenHelp});

  final String role;
  final VoidCallback? onOpenHelp;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.guidance,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        final steps = guideFor(role).take(3).toList();
        return Panel(
          title: isFrench ? 'Comment faire' : 'How to work here',
          trailing: onOpenHelp == null
              ? null
              : TextButton(
                  onPressed: onOpenHelp,
                  child: Text(isFrench ? 'Tout lire' : 'Read all'),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: LamalivaSpace.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c(LamalivaColors.creamDeep),
                          borderRadius: BorderRadius.circular(
                            LamalivaShape.card,
                          ),
                        ),
                        child: Icon(
                          steps[i].icon,
                          size: 17,
                          color: c(LamalivaColors.navy800),
                        ),
                      ),
                      const SizedBox(width: LamalivaSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].title,
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(steps[i].body, style: T.bodyMuted),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The full guide, written per role and readable at any time.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.role, required this.name});

  final String role;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppSettings.language,
      builder: (context, code, _) {
        final steps = guideFor(role);
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            LamalivaSpace.lg,
            LamalivaSpace.lg,
            LamalivaSpace.lg,
            LamalivaSpace.xl,
          ),
          children: [
            Panel(
              padding: const EdgeInsets.all(LamalivaSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFrench ? 'Bienvenue, $name' : 'Welcome, $name',
                    style: T.screenTitle,
                  ),
                  const SizedBox(height: LamalivaSpace.xs),
                  Text(
                    isFrench
                        ? 'Ce guide parle du travail de chaque jour à l’hôtel. '
                              'Votre rôle : $role.'
                        : 'This guide talks about the day-to-day work of the hotel. '
                              'Your role: $role.',
                    style: T.bodyMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: LamalivaSpace.md),
            for (var i = 0; i < steps.length; i++) ...[
              Panel(
                title: steps[i].title,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      steps[i].icon,
                      size: 18,
                      color: c(LamalivaColors.orangeMid),
                    ),
                    const SizedBox(width: LamalivaSpace.sm),
                    Expanded(child: Text(steps[i].body, style: T.bodyMuted)),
                  ],
                ),
              ),
              const SizedBox(height: LamalivaSpace.sm),
            ],
            Text(
              isFrench
                  ? 'Si un écran refuse une action, lisez le message : il dit quoi '
                        'corriger. Rien n’est perdu, l’hôtel garde chaque mouvement.'
                  : 'If a screen refuses an action, read the message: it says what to '
                        'correct. Nothing is lost — the hotel keeps every movement.',
              style: T.micro,
            ),
          ],
        );
      },
    );
  }
}
