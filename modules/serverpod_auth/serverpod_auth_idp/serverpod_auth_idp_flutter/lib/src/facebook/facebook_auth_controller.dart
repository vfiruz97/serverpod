import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';

import 'facebook_sign_in_service.dart';

/// Controller for managing Facebook-based authentication flows.
///
/// This controller handles all the business logic for Facebook authentication,
/// including initialization, sign-in, and authentication event handling.
/// It can be used with any UI implementation.
///
/// Example usage:
/// ```dart
/// final controller = FacebookAuthController(
///   client: client,
///   onAuthenticated: () {
///     // Navigate to home screen
///   },
/// );
///
/// // Initiate sign-in
/// await controller.signIn();
///
/// // Listen to state changes
/// controller.addListener(() {
///   // UI will rebuild automatically
///   // Can use `controller.state` to access the current state.
/// });
/// ```
class FacebookAuthController extends ChangeNotifier {
  /// The Serverpod client instance.
  final ServerpodClientShared client;

  /// Callback when authentication is successful.
  final VoidCallback? onAuthenticated;

  /// Callback when an error occurs during authentication.
  ///
  /// The [error] parameter is an exception that should be shown to the user.
  /// Exceptions that should not be shown to the user are shown in the debug
  /// log, but not passed to the callback.
  final Function(Object error)? onError;

  /// Permissions to request from Facebook.
  ///
  /// The default permissions are `public_profile` and `email`, which will give
  /// access to the user's basic profile information and email address.
  ///
  /// Reference: https://developers.facebook.com/docs/permissions/reference
  final List<String> permissions;

  /// Creates a Facebook authentication controller.
  FacebookAuthController({
    required this.client,
    this.onAuthenticated,
    this.onError,
    this.permissions = defaultPermissions,
  }) {
    unawaited(_initialize());
  }

  /// Default permissions to request from Facebook.
  ///
  /// - `public_profile`: Access to user's ID, name, and profile picture
  /// - `email`: Access to user's email address
  ///
  /// Requests access to user email and read-only profile information.
  static const defaultPermissions = [
    'public_profile',
    'email',
  ];

  FacebookAuthState _state = FacebookAuthState.initializing;

  bool _disposed = false;

  /// The current state of the authentication flow.
  FacebookAuthState get state => _state;

  /// Whether the controller is currently processing a request.
  bool get isLoading => _state == FacebookAuthState.loading;

  /// Whether the user is authenticated.
  bool get isAuthenticated => client.auth.isAuthenticated;

  /// The current error message, if any.
  String? get errorMessage => _error?.toString();

  /// The current error, if any.
  Object? get error => _state == FacebookAuthState.error ? _error : null;
  Object? _error;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Initializes the Facebook Sign-In service.
  Future<void> _initialize() async {
    try {
      await FacebookSignInService.instance.ensureInitialized(
        auth: client.auth,
      );
      _setState(FacebookAuthState.idle);
    } catch (error) {
      _error = error;
      _setState(FacebookAuthState.error);
      onError?.call(error);
    }
  }

  /// Initiates the Facebook Sign-In flow.
  ///
  /// On success, the user will be signed in to both Facebook and the Serverpod
  /// backend. On failure, transitions to error state with the error message.
  ///
  /// If the user cancels the sign-in, the state returns to idle without
  /// triggering an error.
  Future<void> signIn() async {
    if (_state == FacebookAuthState.loading) return;
    _setState(FacebookAuthState.loading);

    try {
      final accessToken = await FacebookSignInService.instance.signIn(
        permissions: permissions,
      );

      if (accessToken == null) {
        // User cancelled the sign-in
        _setState(FacebookAuthState.idle);
        return;
      }

      await _handleServerSideSignIn(accessToken);
    } catch (error) {
      _error = error;
      _setState(FacebookAuthState.error);
      onError?.call(error);
    }
  }

  /// Handles the server-side sign-in process with the Facebook access token.
  Future<void> _handleServerSideSignIn(String accessToken) async {
    try {
      final endpoint = client.getEndpointOfType<EndpointFacebookIdpBase>();
      final authSuccess = await endpoint.login(
        accessToken: accessToken,
      );

      await client.auth.updateSignedInUser(authSuccess);

      _setState(FacebookAuthState.authenticated);
      onAuthenticated?.call();
    } catch (error) {
      _error = error;
      _setState(FacebookAuthState.error);
      onError?.call(error);
    }
  }

  /// Sets the current state of the authentication flow and notifies listeners.
  void _setState(FacebookAuthState newState) {
    if (_disposed) return;
    if (newState != FacebookAuthState.error) _error = null;
    _state = newState;
    notifyListeners();
  }
}

/// Represents the state of the Facebook authentication flow.
enum FacebookAuthState {
  /// Initial state while the controller is being initialized.
  initializing,

  /// Idle state, ready to start authentication.
  idle,

  /// Loading state while processing any request.
  loading,

  /// A request ended with error. The error can be retrieved from the controller.
  error,

  /// Authentication was successful.
  authenticated,
}
