import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/colors.dart';
import 'config/routes.dart';
import 'config/page_transitions.dart';
import 'config/navigator_key.dart';
import 'services/supabase_service.dart';
import 'services/last_seen_pinger.dart';
import 'services/push_notification_service.dart';
import 'services/auth_deep_link_service.dart';
import 'utils/notification_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Allow Google Fonts to fetch Inter at runtime (cached after first load)
  GoogleFonts.config.allowRuntimeFetching = true;
  
  // Set system UI overlay style for dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: JobsyColors.navBarBackground,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Firebase
  await Firebase.initializeApp();
  
  await Supabase.initialize(
    url: SupabaseService.supabaseUrl,
    anonKey: SupabaseService.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await AuthDeepLinkService.initialize();

  // Wire up notification tap → navigation (BEFORE initialize so the
  // callback is ready when getInitialMessage / onMessageOpenedApp fires)
  PushNotificationService.instance.onNotificationTap = navigateFromNotification;

  // Initialize push notifications
  await PushNotificationService.instance.initialize();

  // If the user already has a session on cold start, ping last_seen
  // and register FCM token.
  if (Supabase.instance.client.auth.currentUser != null) {
    LastSeenPinger.ping();
    PushNotificationService.instance.onSignIn();
  }
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.tokenRefreshed) {
      LastSeenPinger.ping();
      PushNotificationService.instance.onSignIn();
    }
    if (data.event == AuthChangeEvent.passwordRecovery) {
      AuthDeepLinkService.navigateToResetPassword();
    }
    // Session expired or explicitly signed out — return to welcome screen
    if (data.event == AuthChangeEvent.signedOut) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.welcome, (route) => false,
      );
    }
  });
  
  runApp(const JobsyApp());
}

class JobsyApp extends StatefulWidget {
  const JobsyApp({super.key});

  @override
  State<JobsyApp> createState() => _JobsyAppState();
}

class _JobsyAppState extends State<JobsyApp> {
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Jobsy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: JobsyColors.employerPrimary,
        scaffoldBackgroundColor: JobsyColors.background,
        colorScheme: const ColorScheme.dark(
          primary: JobsyColors.employerPrimary,
          secondary: JobsyColors.workerPrimary,
          surface: JobsyColors.surface,
          error: JobsyColors.error,
          onPrimary: Color(0xFF0A0A0A),
          onSecondary: Color(0xFF0A0A0A),
          onSurface: JobsyColors.textPrimary,
        ),
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ).apply(
          bodyColor: JobsyColors.textPrimary,
          displayColor: JobsyColors.textPrimary,
        ),
        primaryTextTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().primaryTextTheme,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: JobsyColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: JobsyColors.textPrimary),
          titleTextStyle: GoogleFonts.inter(
            color: JobsyColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: JobsyColors.navBarBackground,
          selectedItemColor: JobsyColors.employerPrimary,
          unselectedItemColor: JobsyColors.textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: JobsyColors.surfaceLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: JobsyColors.border.withOpacity(0.5), width: 0.5),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: JobsyColors.divider,
          thickness: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: JobsyColors.surfaceElevated,
          contentTextStyle: const TextStyle(color: JobsyColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: JobsyColors.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: const TextStyle(
            color: JobsyColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: const TextStyle(
            color: JobsyColors.textSecondary,
            fontSize: 15,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
