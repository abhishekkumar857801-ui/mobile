import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'services/notifications.dart';
import 'services/session.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  session.load();
  runApp(TeamFlowApp());
}

class TeamFlowApp extends StatelessWidget {
  const TeamFlowApp({super.key});

  /// "Bus Ticket" theme, shared with the web app: conductor-navy bars,
  /// ticket-red primary actions, Chivo type. Light scheme because the app is
  /// used in daylight on shop floors and on the move.
  ThemeData _theme(Brightness brightness) {
    final previous = AppColors.dark;
    AppColors.dark = brightness == Brightness.dark; // build this theme from the matching palette
    try {
      return _buildTheme(brightness);
    } finally {
      AppColors.dark = previous;
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.text,
      secondary: AppColors.navy,
      onSecondary: AppColors.cream,
      secondaryContainer: AppColors.surface2,
      onSecondaryContainer: AppColors.text,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.text2,
      surfaceContainerHighest: AppColors.surface2,
      outline: AppColors.muted,
      outlineVariant: AppColors.border,
      error: AppColors.dangerInk,
      onError: AppColors.bg,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.dangerInk,
      inverseSurface: AppColors.text,
      onInverseSurface: AppColors.bg,
      inversePrimary: AppColors.coral,
      surfaceTint: AppColors.navy,
      shadow: AppColors.navy,
      scrim: AppColors.navy,
      surfaceContainer: AppColors.surface2,
      surfaceContainerHigh: AppColors.surface2,
      surfaceContainerLow: AppColors.surface,
      surfaceContainerLowest: AppColors.bg,
    );
    final border = AppColors.border;
    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, fontFamily: 'Figtree');
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'Figtree', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.cream),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: border, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: border, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.navy, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: Size(48, 48),
          side: BorderSide(color: AppColors.borderStrong, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk)),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: AppColors.borderStrong),
        selectedColor: AppColors.navy,
        secondarySelectedColor: AppColors.navy,
        labelStyle: TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w600, color: AppColors.text),
        secondaryLabelStyle: TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w600, color: AppColors.cream),
        checkmarkColor: AppColors.cream,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.navy : AppColors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.cream : AppColors.text),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.cream,
        unselectedLabelColor: AppColors.navyInk,
        indicatorColor: AppColors.cream,
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.cream : AppColors.text2),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.text2,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.cream,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(fontFamily: 'Figtree', color: AppColors.cream),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
      dividerTheme: DividerThemeData(color: border),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.navy),
      sliderTheme: SliderThemeData(activeTrackColor: AppColors.navy, thumbColor: AppColors.navy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeamFlow',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system, // follows the phone's light/dark setting
      builder: (context, child) {
        // Widgets read AppColors directly, so keep it in step with the active
        // theme and redraw everything (state kept) when it flips.
        final dark = Theme.of(context).brightness == Brightness.dark;
        if (AppColors.dark != dark) {
          AppColors.dark = dark;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            void rebuild(Element e) {
              e.markNeedsBuild();
              e.visitChildren(rebuild);
            }
            (context as Element).visitChildren(rebuild);
          });
        }
        return child!;
      },
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.ready) return Scaffold(body: Center(child: CircularProgressIndicator()));
          if (!session.signedIn) return LoginScreen();
          if (session.locked) return LockScreen();
          return HomeScreen();
        },
      ),
    );
  }
}
