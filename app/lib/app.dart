import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/applicant/a1_splash.dart';
import 'screens/applicant/a2_role.dart';
import 'screens/applicant/a3_auth.dart';
import 'screens/applicant/a4_details.dart';
import 'screens/applicant/a5_kyc.dart';
import 'screens/applicant/a6_documents.dart';
import 'screens/applicant/a7_sign.dart';
import 'screens/applicant/a8_processing.dart';
import 'screens/applicant/a9_result.dart';
import 'screens/applicant/a10_home.dart';
import 'screens/officer/o1_queue.dart';
import 'screens/officer/o2_file.dart';
import 'screens/officer/o3_login.dart';
import 'state/app_state.dart';
import 'state/scope.dart';
import 'theme/theme.dart';

/// Thirteen screens. If a fourteenth appears, it is scope creep.
class FastTrackApp extends StatefulWidget {
  const FastTrackApp({super.key, required this.state});
  final AppState state;

  @override
  State<FastTrackApp> createState() => _FastTrackAppState();
}

class _FastTrackAppState extends State<FastTrackApp> {
  late final GoRouter _router = buildRouter(widget.state);

  @override
  Widget build(BuildContext context) => AppScope(
    state: widget.state,
    child: MaterialApp.router(
      title: 'FastTrack',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    ),
  );
}

const _public = {'/', '/role', '/auth', '/officer/login'};

GoRouter buildRouter(AppState s) => GoRouter(
  initialLocation: '/',
  refreshListenable: s,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final officerArea = loc.startsWith('/officer') && loc != '/officer/login';

    if (officerArea) {
      if (!s.signedIn) return '/officer/login';
      if (!s.isOfficer) return '/home'; // wrong role bounces to A10
      return null;
    }
    if (_public.contains(loc)) return null;
    if (!s.signedIn) return '/auth';
    if (s.isOfficer) return '/officer';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/role', builder: (_, _) => const RoleScreen()),
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    GoRoute(path: '/details', builder: (_, _) => const DetailsScreen()),
    GoRoute(path: '/kyc', builder: (_, _) => const KycScreen()),
    GoRoute(path: '/documents', builder: (_, _) => const DocumentsScreen()),
    GoRoute(path: '/sign', builder: (_, _) => const SignScreen()),
    GoRoute(path: '/processing', builder: (_, _) => const ProcessingScreen()),
    GoRoute(path: '/result', builder: (_, _) => const ResultScreen()),
    GoRoute(path: '/home', builder: (_, _) => const ApplicationHomeScreen()),
    GoRoute(path: '/officer/login', builder: (_, _) => const OfficerLoginScreen()),
    GoRoute(path: '/officer', builder: (_, _) => const QueueScreen()),
    GoRoute(
      path: '/officer/applications/:id',
      builder: (_, st) => OfficerFileScreen(applicationId: st.pathParameters['id']!),
    ),
  ],
);
