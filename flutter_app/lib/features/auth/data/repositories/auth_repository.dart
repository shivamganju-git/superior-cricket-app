import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../domain/models/user_model.dart' as app_models;

class AuthRepository {
  final _supabase = SupabaseConfig.client;

  // Check if email exists in auth.users (across all providers)
  // DEPRECATED: We no longer check profiles for email as it is a security risk
  Future<bool> _emailExists(String email) async {
    return false; // Always return false to skip this check and let Supabase Auth handle it
  }

  // Check if email is registered via Google
  // DEPRECATED: Scanning profiles is a security risk
  Future<bool> _isGoogleUser(String email) async {
    return false;
  }

  // Generate unique username from name
  Future<String> _generateUniqueUsername(String name) async {
    // Clean name: lowercase, remove spaces, remove special chars
    String baseUsername = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
    
    // Ensure minimum length
    if (baseUsername.isEmpty) {
      baseUsername = 'user';
    }
    
    // Limit length
    if (baseUsername.length > 20) {
      baseUsername = baseUsername.substring(0, 20);
    }
    
    // Check if username exists and generate unique one
    String username = baseUsername;
    int counter = 1;
    int maxAttempts = 1000; // Prevent infinite loop
    
    while (counter < maxAttempts) {
      final exists = await _usernameExists(username);
      if (!exists) {
        return username;
      }
      
      // Append number
      final suffix = counter.toString();
      final maxLength = 20 - suffix.length;
      if (maxLength > 0) {
        username = baseUsername.substring(0, maxLength) + suffix;
      } else {
        username = 'user$suffix';
      }
      counter++;
    }
    
    // Fallback: use timestamp
    return 'user${DateTime.now().millisecondsSinceEpoch}';
  }

  // Check if username exists (using case-insensitive comparison)
  Future<bool> _usernameExists(String username) async {
    try {
      final normalizedUsername = username.toLowerCase().trim();
      final response = await _supabase
          .from('profiles')
          .select('username')
          .ilike('username', normalizedUsername)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<app_models.AuthSession> login(String email, String password) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // Check if email exists and might be a Google user
      final emailExists = await _emailExists(normalizedEmail);
      if (emailExists) {
        // Try to login - if it fails with "Invalid login credentials",
        // it might be a Google user, but we can't be 100% sure
        // So we'll let Supabase handle the error
      }

      final response = await _supabase.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Login failed: User not found');
      }

      if (response.session == null) {
        throw Exception('Login failed: No session created. Please check your email for verification.');
      }

      // Get or create user profile
      final profile = await _getOrCreateProfile(response.user!);

      // Role not in new schema, default to player
      final role = app_models.UserRole.player;

      return app_models.AuthSession(
        token: response.session!.accessToken,
        refreshToken: response.session!.refreshToken ?? '',
        user: app_models.User(
          id: response.user!.id,
          email: response.user!.email ?? normalizedEmail,
          name: profile['full_name'] as String? ?? 
                normalizedEmail.split('@')[0],
          username: profile['username'] as String?,
          subscriptionPlan: profile['subscription_plan'] as String?,
          role: role,
          avatar: profile['avatar_url'] as String?,
          phone: null,

          createdAt: DateTime.parse(profile['created_at'] as String),
          updatedAt: DateTime.parse(profile['updated_at'] as String),
        ),
        expiresAt: response.session!.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (response.session!.expiresAt as num).toInt() * 1000)
            : DateTime.now().add(const Duration(days: 7)),
      );
    } on AuthException catch (e) {
      // Handle specific errors
      if (e.message.contains('Invalid login credentials')) {
        // Check if email exists - if yes, might be Google user
        final emailExists = await _emailExists(email.toLowerCase().trim());
        if (emailExists) {
          // We can't confirm it's Google without checking profiles (unsafe), 
          // but "Invalid Login" usually means either wrong password or wrong provider.
          // We'll let the generic error handle it or hint at Google.
        }
        throw Exception('Invalid email or password. Please check your credentials.');
      }
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      // Other errors
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  Future<app_models.AuthSession> loginWithGoogle() async {
    try {
      // Sign in with Google OAuth
      // With LaunchMode.externalApplication, Supabase automatically launches the browser
      // The method returns true if the OAuth flow was initiated successfully
      final success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
        scopes: 'openid email profile https://www.googleapis.com/auth/youtube',
      );

      // If successful, the OAuth flow will complete in the browser
      // When done, Supabase will redirect to our deep link (cricplay://login-callback)
      // The session will be automatically handled by Supabase when the deep link is received
      // We throw a special exception to indicate the flow has started
      // The callback handler will complete the authentication
      if (success) {
        throw Exception('OAuth flow initiated. Please complete authentication in the browser.');
      } else {
        throw Exception('Failed to initiate OAuth flow. Please try again.');
      }
    } on AuthException catch (e) {
      throw Exception('Google login failed: ${e.message}');
    } catch (e) {
      // Re-throw our custom message
      if (e.toString().contains('OAuth flow initiated')) {
        rethrow;
      }
      throw Exception('Google login failed: ${e.toString()}');
    }
  }

  // Handle Google OAuth callback (call this after redirect)
  Future<app_models.AuthSession> handleGoogleAuthCallback() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        throw Exception('No active session found');
      }

      final user = session.user;
      if (user == null) {
        throw Exception('User not found in session');
      }

      // Check if email already exists with different provider
      final email = user.email;
      if (email != null) {
        final emailExists = await _emailExists(email);
        if (emailExists) {
          // Check if it's a Google user or email/password user
          // If email/password user exists, we should link accounts
          // For now, we'll allow login and link the profile
        }
      }

      // Get or create profile with username generation
      final profile = await _getOrCreateProfile(user);

      // Role not in new schema, default to player
      final role = app_models.UserRole.player;

      return app_models.AuthSession(
        token: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        user: app_models.User(
          id: user.id,
          email: user.email ?? '',
          name: profile['full_name'] as String? ?? 
                user.userMetadata?['name'] ?? 
                'User',
          username: profile['username'] as String?,
          subscriptionPlan: profile['subscription_plan'] as String?,
          role: role,
          avatar: profile['avatar_url'] as String? ?? user.userMetadata?['avatar_url'],
          phone: null, // Phone not in new schema
          createdAt: DateTime.parse(profile['created_at'] as String),
          updatedAt: DateTime.parse(profile['updated_at'] as String),
        ),
        expiresAt: session.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
            : DateTime.now().add(const Duration(days: 7)),
      );
    } catch (e) {
      throw Exception('Failed to handle Google auth: ${e.toString()}');
    }
  }

  Future<app_models.AuthSession> register(String email, String password, String name) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // Check if email already exists
      final emailExists = await _emailExists(normalizedEmail);
      if (emailExists) {
        // Check if it's a Google user
        // Since we can't directly check provider, we'll check if user can login with password
        // If email exists but password login fails, it's likely a Google user
        throw Exception('This email is already registered via Google login. Please sign in using Google.');
      }

      final response = await _supabase.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'name': name,
        },
        emailRedirectTo: SupabaseConfig.redirectUrl,
      );

      if (response.user == null) {
        throw Exception('Registration failed: User not created');
      }

      // Get or create user profile (trigger handles creation)
      final profile = await _getOrCreateProfile(response.user!);

      // Check if we have a session (email confirmation disabled)
      if (response.session == null) {
        throw Exception('Registration successful but email verification required. Please check your email.');
      }

      // Role not in new schema, default to player
      final role = app_models.UserRole.player;

      return app_models.AuthSession(
        token: response.session!.accessToken,
        refreshToken: response.session!.refreshToken ?? '',
        user: app_models.User(
          id: response.user!.id,
          email: normalizedEmail,
          name: profile['full_name'] as String? ?? name,
          username: profile['username'] as String?,
          subscriptionPlan: profile['subscription_plan'] as String?,
          role: role,
          avatar: profile['avatar_url'] as String?,
          phone: null,

          createdAt: DateTime.parse(profile['created_at'] as String),
          updatedAt: DateTime.parse(profile['updated_at'] as String),
        ),
        expiresAt: response.session!.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (response.session!.expiresAt as num).toInt() * 1000)
            : DateTime.now().add(const Duration(days: 7)),
      );
    } on AuthException catch (e) {
      // Handle specific Supabase errors
      if (e.message.contains('already registered') || e.message.contains('already exists')) {
        throw Exception('This email is already registered. Please sign in instead.');
      }
      throw Exception('Registration failed: ${e.message}');
    } catch (e) {
      // Other errors
      final errorMsg = e.toString();
      if (errorMsg.contains('already registered') || errorMsg.contains('Google login')) {
        // Re-throw our custom message
        throw e;
      } else if (errorMsg.contains('duplicate key') || errorMsg.contains('already exists')) {
        throw Exception('An account with this email already exists. Please login instead.');
      } else if (errorMsg.contains('profiles')) {
        throw Exception('Registration successful but profile creation failed. Please try logging in.');
      }
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  Future<app_models.User> getCurrentUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      final profile = await _getOrCreateProfile(user);

      // Role not in new schema, default to player
      final role = app_models.UserRole.player;

      return app_models.User(
        id: user.id,
        email: user.email ?? '',
        name: profile['full_name'] as String? ?? 
              user.email?.split('@')[0] ?? 
              'User',
        username: profile['username'] as String?,
        subscriptionPlan: profile['subscription_plan'] as String?,
        role: role,
        avatar: profile['avatar_url'] as String?,
        phone: null, // Phone not in new schema
        createdAt: DateTime.parse(profile['created_at'] as String),
        updatedAt: DateTime.parse(profile['updated_at'] as String),
      );
    } catch (e) {
      throw Exception('Failed to get current user: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> _getOrCreateProfile(User supabaseUser) async {
    try {
      // Profile is automatically created by trigger on_auth_user_created
      // Just fetch it - if it doesn't exist, wait a moment and retry
      var response = await _supabase
          .from('profiles')
          .select()
          .eq('id', supabaseUser.id)
          .maybeSingle();

      // If profile doesn't exist yet (race condition), wait and retry
      if (response == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        response = await _supabase
            .from('profiles')
            .select()
            .eq('id', supabaseUser.id)
            .maybeSingle();
      }

      // If still doesn't exist, trigger might not have fired - create manually
      if (response == null) {
        // Use database function to generate username
        final name = supabaseUser.userMetadata?['name'] ?? 
                    supabaseUser.email?.split('@')[0] ?? 
                    'User';
        
        // Call the database function to generate unique username
        final usernameResult = await _supabase.rpc(
          'generate_unique_username',
          params: {'base_name': name},
        );
        
        final username = usernameResult as String? ?? 
                        name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        
        final profileData = {
          'id': supabaseUser.id,
          // 'email': supabaseUser.email?.toLowerCase().trim(), // REMOVED: Email in public profiles is insecure
          'full_name': name,

          'username': username,
          'avatar_url': supabaseUser.userMetadata?['avatar_url'],
        };

        await _supabase.from('profiles').insert(profileData);

        // Fetch the newly created profile
        response = await _supabase
            .from('profiles')
            .select()
            .eq('id', supabaseUser.id)
            .single();
      }

      return response as Map<String, dynamic>;
    } catch (e) {
      // If profile creation fails, return minimal profile
      print('Warning: Profile creation/retrieval failed: $e');
      final name = supabaseUser.userMetadata?['name'] ?? 
                  supabaseUser.email?.split('@')[0] ?? 
                  'User';
      
      return {
        'id': supabaseUser.id,
        // 'email': supabaseUser.email?.toLowerCase().trim(),
        'full_name': name,

        'username': name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
        'avatar_url': supabaseUser.userMetadata?['avatar_url'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }
}

