import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';
import 'data/demo_repository.dart';
import 'data/neon_repository.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard from docs/00-START-HERE.md: live provider code must not ship in v1.
  if (Env.liveKyc) {
    throw StateError('LIVE_KYC must be false in the demo build.');
  }

  final FastTrackRepository repo;
  if (Env.hasNeon) {
    // Only the function URL reaches the client; it holds no secrets.
    repo = await NeonRepository.open(Env.neonApiUrl);
  } else if (Env.hasSupabase) {
    // The anon / publishable key is the only key the client ever holds.
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    repo = SupabaseRepository(Supabase.instance.client);
  } else {
    repo = await DemoRepository.open();
  }

  final state = AppState(repo);
  if (state.signedIn) {
    try {
      await state.loadApplicant();
    } catch (_) {
      // Session restore is best-effort; the router sends users to /auth.
    }
  }

  runApp(FastTrackApp(state: state));
}
