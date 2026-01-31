import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/tournament_model.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/pages/signup_page.dart';
import '../../features/auth/presentation/pages/email_verification_callback_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../core/widgets/loading_screen.dart';
import '../../core/widgets/splash_screen.dart';
import '../../core/widgets/main_shell.dart';
import '../../features/player/presentation/pages/player_dashboard_page.dart';
import '../../features/player/presentation/pages/scorecards_page.dart';
import '../../features/player/presentation/pages/leaderboards_page.dart';
import '../../features/coach/presentation/pages/coach_dashboard_page.dart';
import '../../features/coach/presentation/pages/team_management_page.dart';
import '../../features/coach/presentation/pages/player_monitoring_page.dart';
import '../../features/tournament/presentation/pages/tournament_list_page.dart';
import '../../features/tournament/presentation/pages/tournament_details_page.dart';
import '../../features/tournament/presentation/pages/tournament_home_page.dart';
import '../../features/tournament/presentation/pages/fixtures_page.dart';
import '../../features/tournament/presentation/pages/points_table_page.dart';
import '../../features/tournament/presentation/pages/tournaments_arena_page.dart';
import '../../features/tournament/presentation/pages/add_teams_page.dart';
import '../../features/tournament/presentation/pages/add_tournament_page.dart';
import '../../features/tournament/presentation/pages/tournament_leaderboard_page.dart';
import '../../features/academy/presentation/pages/academy_dashboard_page.dart';
import '../../features/academy/presentation/pages/academy_detail_page.dart';
import '../../features/academy/presentation/pages/training_programs_page.dart';
import '../../features/match/presentation/pages/match_center_page.dart';
import '../../features/match/presentation/pages/match_details_page.dart';
import '../../features/match/presentation/pages/match_list_page.dart';
import '../../features/match/presentation/pages/match_detail_screen.dart';
import '../../features/match/presentation/pages/match_detail_page_comprehensive.dart';
import '../../features/pro/presentation/pages/pro_page.dart';
import '../../features/admin/presentation/pages/admin_dashboard_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/mycricket/presentation/pages/my_cricket_page.dart';
import '../../features/shop/presentation/pages/shop_page.dart';
import '../../features/mycricket/presentation/pages/scorecard_page.dart';
import '../../features/mycricket/presentation/pages/create_match_page.dart';
import '../../features/mycricket/presentation/pages/my_team_squad_page.dart';
import '../../features/mycricket/presentation/pages/opponent_team_squad_page.dart';
import '../../features/mycricket/presentation/pages/toss_page.dart';
import '../../features/mycricket/presentation/pages/initial_players_setup_page.dart';
import '../../features/live/presentation/pages/live_screen.dart';
import '../../features/live/presentation/pages/go_live_screen.dart';
import '../../features/live/presentation/pages/watch_live_screen.dart';
import '../../features/match/presentation/pages/commentary_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/subscription/presentation/pages/subscription_page.dart';
import '../../core/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  
  return GoRouter(
    initialLocation: '/loading',
    redirect: (context, state) {
      final currentLocation = state.matchedLocation;
      final isLoggedIn = authState.isAuthenticated;
      final isLoginPage = currentLocation == '/login' || 
                         currentLocation == '/onboarding' ||
                         currentLocation == '/signup';
      final isLoadingPage = currentLocation == '/loading';
      final isCallbackPage = currentLocation == '/login-callback';
      
      // If auth is still loading, stay on loading page or redirect to it
      // But allow callback page to process OAuth
      if (authState.isLoading) {
        if (isCallbackPage) {
          return null; // Let callback page process
        }
        if (!isLoadingPage) {
          return '/loading';
        }
        return null; // Stay on current page
      }
      
      // PRIORITY 1: If logged in and on a login/loading/callback page, redirect to home immediately
      if (isLoggedIn && (isLoginPage || isLoadingPage || isCallbackPage)) {
        // Force redirect to dashboard when authenticated
        return '/';
      }
      
      // PRIORITY 2: If not logged in and on loading page (auth check complete), redirect to login
      if (!isLoggedIn && isLoadingPage) {
        return '/login';
      }
      
      // PRIORITY 3: If not logged in and on callback page (OAuth failed), redirect to login
      if (!isLoggedIn && isCallbackPage) {
        return '/login';
      }
      
      // PRIORITY 4: If not logged in and trying to access protected routes, redirect to login
      if (!isLoggedIn && !isLoginPage && !isLoadingPage && !isCallbackPage) {
        return '/login';
      }
      
      // No redirect needed
      return null;
    },
    routes: [
      // Splash Screen Route (shows first on app launch)
      GoRoute(
        path: '/loading',
        builder: (context, state) => const SplashScreen(),
      ),
      // Auth Routes
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignUpPage(),
      ),
      // Email verification callback (deep link handler)
      GoRoute(
        path: '/login-callback',
        builder: (context, state) {
          // Handle both success and error cases
          final code = state.uri.queryParameters['code'];
          final type = state.uri.queryParameters['type'];
          final error = state.uri.queryParameters['error'];
          final errorCode = state.uri.queryParameters['error_code'];
          final errorDescription = state.uri.queryParameters['error_description'];
          
          return EmailVerificationCallbackPage(
            code: code ?? error, // Pass error as code if no code
            type: type,
          );
        },
      ),
      
      // Main Shell Routes
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Dashboard Routes
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          
          // My Cricket Route
          GoRoute(
            path: '/my-cricket',
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              return MyCricketPage(initialTab: tab);
            },
          ),
          
          // Profile Route
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      
      // Other Routes (Outside of Shell)
      GoRoute(
        path: '/pro',
        builder: (context, state) => const ProPage(),
      ),
      GoRoute(
        path: '/match-center',
        builder: (context, state) => const MatchCenterPage(),
      ),
      GoRoute(
        path: '/matches',
        builder: (context, state) => const MatchCenterPage(),
      ),
      GoRoute(
        path: '/matches/:id',
        builder: (context, state) {
          final matchId = state.pathParameters['id']!;
          return MatchDetailPageComprehensive(matchId: matchId);
        },
      ),
      GoRoute(
        path: '/create-match',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CreateMatchPage(
            tournamentId: extra?['tournamentId'],
          );
        },
      ),
      GoRoute(
        path: '/my-team-squad',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MyTeamSquadPage(
            teamName: extra?['teamName'] ?? 'My Team',
            initialPlayers: extra?['players'] ?? [],
          );
        },
      ),
      GoRoute(
        path: '/opponent-team-squad',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OpponentTeamSquadPage(
            teamName: extra?['teamName'] ?? 'Opponent Team',
            initialPlayers: extra?['players'] ?? [],
          );
        },
      ),
      GoRoute(
        path: '/toss',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TossPage(
            myTeam: extra?['myTeam'] ?? 'My Team',
            opponentTeam: extra?['opponentTeam'] ?? 'Opponent Team',
            overs: extra?['overs'] ?? '20',
            groundType: extra?['groundType'] ?? 'Turf',
            ballType: extra?['ballType'] ?? 'Leather',
            myTeamPlayers: extra?['myTeamPlayers'] ?? [],
            opponentTeamPlayers: extra?['opponentTeamPlayers'] ?? [],
            initialStriker: extra?['initialStriker'],
            initialNonStriker: extra?['initialNonStriker'],
            initialBowler: extra?['initialBowler'],
            youtubeVideoId: extra?['youtubeVideoId'],
            matchId: extra?['matchId'],
            team1Id: extra?['team1Id'],
            team2Id: extra?['team2Id'],
          );
        },
      ),
      GoRoute(
        path: '/initial-players-setup',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return InitialPlayersSetupPage(
            myTeam: extra?['myTeam'] ?? 'My Team',
            opponentTeam: extra?['opponentTeam'] ?? 'Opponent Team',
            overs: extra?['overs'] ?? '20',
            groundType: extra?['groundType'] ?? 'Turf',
            ballType: extra?['ballType'] ?? 'Leather',
            myTeamPlayers: extra?['myTeamPlayers'] ?? [],
            opponentTeamPlayers: extra?['opponentTeamPlayers'] ?? [],
            tossWinner: extra?['tossWinner'],
            tossChoice: extra?['tossChoice'],
            matchId: extra?['matchId'],
            youtubeVideoId: extra?['youtubeVideoId'],
            team1Id: extra?['team1Id'],
            team2Id: extra?['team2Id'],
          );
        },
      ),
      
      // Player Routes
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerDashboardPage(),
      ),
      GoRoute(
        path: '/player/scorecards',
        builder: (context, state) => const ScorecardsPage(),
      ),
      GoRoute(
        path: '/player/leaderboards',
        builder: (context, state) => const LeaderboardsPage(),
      ),
      
      // Coach Routes
      GoRoute(
        path: '/coach',
        builder: (context, state) => const CoachDashboardPage(),
      ),
      GoRoute(
        path: '/coach/teams/:id',
        builder: (context, state) {
          final teamId = state.pathParameters['id']!;
          return TeamManagementPage(teamId: teamId);
        },
      ),
      GoRoute(
        path: '/coach/players',
        builder: (context, state) => const PlayerMonitoringPage(),
      ),
      
      // Tournament Routes
      GoRoute(
        path: '/tournament',
        builder: (context, state) => const TournamentListPage(),
      ),
      GoRoute(
        path: '/tournaments-arena',
        builder: (context, state) => const TournamentsArenaPage(),
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (context, state) {
          final tournamentId = state.pathParameters['id']!;
          return TournamentHomePage(tournamentId: tournamentId);
        },
      ),
      GoRoute(
        path: '/tournament/:id/fixtures',
        builder: (context, state) {
          final tournamentId = state.pathParameters['id']!;
          return FixturesPage(tournamentId: tournamentId);
        },
      ),
      GoRoute(
        path: '/tournament/:id/points',
        builder: (context, state) {
          final tournamentId = state.pathParameters['id']!;
          return PointsTablePage(tournamentId: tournamentId);
        },
      ),
      GoRoute(
        path: '/create-tournament',
        builder: (context, state) {
          final tournament = state.extra as TournamentModel?;
          return AddTournamentPage(initialTournament: tournament);
        },
      ),
      GoRoute(
        path: '/tournament/:id/add-teams',
        builder: (context, state) {
          final tournamentId = state.pathParameters['id']!;
          return AddTeamsPage(tournamentId: tournamentId);
        },
      ),
      GoRoute(
        path: '/tournament/:id/leaderboard',
        builder: (context, state) {
          final tournamentId = state.pathParameters['id']!;
          return TournamentLeaderboardPage(tournamentId: tournamentId);
        },
      ),
      
      // Academy Routes
      GoRoute(
        path: '/academy',
        builder: (context, state) => const AcademyDashboardPage(),
      ),
      GoRoute(
        path: '/academy-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AcademyDetailPage(academy: extra ?? {});
        },
      ),
      GoRoute(
        path: '/academy/:id/programs',
        builder: (context, state) {
          final academyId = state.pathParameters['id']!;
          return TrainingProgramsPage(academyId: academyId);
        },
      ),
      
      // Admin Routes
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardPage(),
      ),
      
      // Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/shop',
        builder: (context, state) => const ShopPage(),
      ),
      GoRoute(
        path: '/scorecard',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ScorecardPage(
            matchId: extra?['matchId'],
            team1: extra?['myTeam'] ?? extra?['team1'] ?? 'Team 1',
            team2: extra?['opponentTeam'] ?? extra?['team2'] ?? 'Team 2',
            overs: extra?['overs'] != null ? int.tryParse(extra!['overs'].toString()) : 20,
            maxOversPerBowler: extra?['maxOversPerBowler'] != null 
                ? int.tryParse(extra!['maxOversPerBowler'].toString()) 
                : null,
            youtubeVideoId: extra?['youtubeVideoId'], // YouTube video ID for live stream
            myTeamPlayers: extra?['myTeamPlayers'] != null 
                ? List<String>.from(extra!['myTeamPlayers']) 
                : null,
            opponentTeamPlayers: extra?['opponentTeamPlayers'] != null
                ? List<String>.from(extra!['opponentTeamPlayers'])
                : null,
            initialStriker: extra?['initialStriker'],
            initialNonStriker: extra?['initialNonStriker'],
            initialBowler: extra?['initialBowler'],
            tossWinner: extra?['tossWinner'],
            tossChoice: extra?['tossChoice'],
          );
        },
      ),
      // Live Stream Route
      GoRoute(
        path: '/live',
        builder: (context, state) {
          final channelHandle = state.uri.queryParameters['channel'];
          final videoId = state.uri.queryParameters['videoId'];
          return LiveScreen(
            channelHandle: channelHandle,
            videoId: videoId,
          );
        },
      ),
      GoRoute(
        path: '/go-live',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GoLiveScreen(
            matchId: extra?['matchId'] ?? '',
            matchTitle: extra?['matchTitle'] ?? 'Live Match',
            isDraft: extra?['isDraft'] ?? false,
          );
        },
      ),
      GoRoute(
        path: '/watch-live/:matchId',
        builder: (context, state) {
          final matchId = state.pathParameters['matchId']!;
          return WatchLiveScreen(matchId: matchId);
        },
      ),
      // Commentary Route
      GoRoute(
        path: '/commentary/:matchId',
        builder: (context, state) {
          final matchId = state.pathParameters['matchId']!;
          // Match status will be fetched by CommentaryPage if needed
          return CommentaryPage(matchId: matchId, showAppBar: true);
        },
      ),
      // Subscription Route
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionPage(),
      ),
      // Notifications Route
      GoRoute(
        path: '/notifications',
        builder: (context, state) {
          return const NotificationsPage();
        },
      ),
    ],
  );
});

