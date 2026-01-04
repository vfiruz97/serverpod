import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

/// Service to manage Facebook Sign-In and ensure it is only initialized once
/// throughout the app lifetime.
class FacebookSignInService {
  /// Singleton instance of the [FacebookSignInService].
  static final FacebookSignInService instance =
      FacebookSignInService._internal();

  /// Convenience getter for the [FacebookAuth.instance]. Be sure to call
  /// [ensureInitialized] before calling methods on the returned instance.
  static final facebookAuth = FacebookAuth.instance;

  FacebookSignInService._internal();

  final _initializedClients = <int>{};

  /// Ensures that Facebook Sign-In is initialized.
  ///
  /// This method is idempotent and can be called multiple times for the same
  /// client. Multiple clients can be registered by calling this method multiple
  /// times with different clients. However, note that only the first call will
  /// initialize the Facebook Sign-In.
  ///
  /// The [auth] is used to register a sign-out hook to logout from Facebook
  /// when the user signs out from the app. This prevents the user from being
  /// signed in back automatically, which would undo the signing out.
  ///
  /// For web and macOS platforms, the [appId] is required for initialization.
  /// If not provided, it will try to load from the `FACEBOOK_APP_ID` environment
  /// variable. For Android and iOS platforms, configuration is done through
  /// native files and this parameter is ignored.
  ///
  /// The optional [cookie], [xfbml], and [version] parameters are only used for
  /// web and macOS platforms and will be passed to the Facebook JavaScript SDK.
  ///
  /// Platform-specific configuration requirements:
  /// - Android: Configure Facebook App ID in AndroidManifest.xml and strings.xml
  /// - iOS: Configure Facebook App ID in Info.plist
  /// - Web: Requires [appId] parameter or FACEBOOK_APP_ID environment variable
  /// - macOS: Requires [appId] parameter or FACEBOOK_APP_ID environment variable,
  ///   plus additional keychain and network permissions in Info.plist
  ///
  /// References:
  /// - Web setup: https://facebook.meedu.app/docs/7.x.x/web
  /// - macOS setup: https://facebook.meedu.app/docs/7.x.x/macos
  Future<FacebookAuth> ensureInitialized({
    required FlutterAuthSessionManager auth,
    String? appId,
    bool cookie = true,
    bool xfbml = true,
    String version = 'v15.0',
  }) async {
    if (_initializedClients.contains(identityHashCode(auth))) {
      return facebookAuth;
    }

    await _withMutexOneTimeInit(() async {
      // Web and macOS platforms require explicit initialization
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
        appId ??= _getAppIdFromEnvVar();

        if (appId == null) {
          throw ArgumentError(
            'Facebook App ID is required for web and macOS platforms. '
            'Either provide it as a parameter or set the "FACEBOOK_APP_ID" '
            'environment variable.',
          );
        }

        await facebookAuth.webAndDesktopInitialize(
          appId: appId!,
          cookie: cookie,
          xfbml: xfbml,
          version: version,
        );
      }

      // For Android and iOS, SDK initialization happens automatically via platform channels
    });

    _initializeClient(auth);
    return facebookAuth;
  }

  void _initializeClient(FlutterAuthSessionManager auth) {
    auth.authInfoListenable.addListener(() {
      if (!auth.isAuthenticated) {
        unawaited(
          facebookAuth.logOut().onError(
            (e, _) =>
                debugPrint('Failed to sign out from Facebook: ${e.toString()}'),
          ),
        );
      }
    });

    _initializedClients.add(identityHashCode(auth));
  }

  Completer<void>? _facebookSignInInit;

  Future<void> _withMutexOneTimeInit(Future<void> Function() initFunc) async {
    if (_facebookSignInInit?.isCompleted ?? false) return;

    var signInInitCompleter = _facebookSignInInit;
    if (signInInitCompleter != null) {
      await signInInitCompleter.future;
    } else {
      signInInitCompleter = Completer();
      _facebookSignInInit = signInInitCompleter;

      try {
        await initFunc();
        signInInitCompleter.complete();
      } catch (e) {
        signInInitCompleter.completeError(e);
        _facebookSignInInit = null;
        rethrow;
      }
    }
  }

  /// Signs in with Facebook and returns the access token.
  ///
  /// Requests the specified [permissions] from Facebook. By default, requests
  /// 'public_profile' and 'email' permissions.
  ///
  /// Returns the access token if sign-in is successful, or null if the user
  /// cancels or an error occurs.
  ///
  /// Reference: https://facebook.meedu.app/docs/7.x.x/usage
  Future<String?> signIn({
    List<String> permissions = const ['public_profile', 'email'],
  }) async {
    try {
      final LoginResult result = await facebookAuth.login(
        permissions: permissions,
      );

      if (result.status == LoginStatus.success) {
        return result.accessToken?.tokenString;
      } else if (result.status == LoginStatus.cancelled) {
        // User cancelled the login
        return null;
      } else {
        // Login failed
        throw Exception('Facebook login failed: ${result.message}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Signs out from Facebook.
  ///
  /// This clears the Facebook session and any cached credentials.
  Future<void> signOut() async {
    await facebookAuth.logOut();
  }

  /// Gets the current access token if the user is already logged in.
  ///
  /// Returns null if no valid access token exists.
  Future<String?> getCurrentAccessToken() async {
    final AccessToken? accessToken = await facebookAuth.accessToken;
    return accessToken?.tokenString;
  }

  /// Checks if the user is currently logged in to Facebook.
  Future<bool> isLoggedIn() async {
    final accessToken = await getCurrentAccessToken();
    return accessToken != null;
  }

  /// Checks if the Facebook Web SDK was successfully initialized.
  ///
  /// This is only relevant for web and macOS platforms. Returns true on
  /// Android and iOS platforms.
  ///
  /// On web, the SDK initialization can fail due to missing configuration or
  /// content blockers. You can use this method to check if initialization
  /// succeeded before attempting to use Facebook authentication.
  Future<bool> isWebSdkInitialized() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS) {
      return true;
    }
    return facebookAuth.isWebSdkInitialized;
  }
}

/// Expose convenient methods on [FlutterAuthSessionManager].
extension FacebookSignInExtension on FlutterAuthSessionManager {
  /// Initializes Facebook Sign-In for the client.
  ///
  /// This method is idempotent and can be called multiple times and from
  /// multiple clients. However, note that only the first call will initialize
  /// the Facebook Sign-In.
  ///
  /// Upon initialization, a sign-out hook is registered to sign out from Facebook
  /// when the user signs out from the app. This prevents the user from being
  /// signed in back automatically, which would undo the signing out.
  ///
  /// For web and macOS platforms, the [appId] is required for initialization.
  /// If not provided, it will try to load from the `FACEBOOK_APP_ID` environment
  /// variable. For Android and iOS platforms, configuration is done through
  /// native files and this parameter is ignored.
  ///
  /// The optional [cookie], [xfbml], and [version] parameters are only used for
  /// web and macOS platforms and will be passed to the Facebook JavaScript SDK.
  ///
  /// Platform-specific setup guides:
  /// - Android: https://facebook.meedu.app/docs/7.x.x/android
  /// - iOS: https://facebook.meedu.app/docs/7.x.x/ios
  /// - Web: https://facebook.meedu.app/docs/7.x.x/web
  /// - macOS: https://facebook.meedu.app/docs/7.x.x/macos
  Future<void> initializeFacebookSignIn({
    String? appId,
    bool cookie = true,
    bool xfbml = true,
    String version = 'v15.0',
  }) async {
    await FacebookSignInService.instance.ensureInitialized(
      auth: this,
      appId: appId,
      cookie: cookie,
      xfbml: xfbml,
      version: version,
    );
  }

  /// Completely disconnects the user's Facebook account from your app and revokes
  /// all previous authorizations. This removes the app's access permissions
  /// entirely, meaning the user will need to go through the full authorization
  /// flow again on the next sign-in, including the account picker and consent
  /// screens.
  Future<void> disconnectFacebookAccount() async {
    final signIn = await FacebookSignInService.instance.ensureInitialized(
      auth: this,
    );
    await signIn.logOut();

    // NOTE: This delay prevents the Facebook Sign-In button from rendering
    // before the disconnect process is complete. Without this, the Sign-In
    // screen will render the button still showing the user as signed in.
    await Future.delayed(const Duration(milliseconds: 300));
    await signOutDevice();
  }
}

String? _getAppIdFromEnvVar() {
  return const bool.hasEnvironment('FACEBOOK_APP_ID')
      ? const String.fromEnvironment('FACEBOOK_APP_ID')
      : null;
}
