import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';

import '../../../../../core.dart';
import 'facebook_idp_config.dart';

/// Details of the Facebook Account.
typedef FacebookAccountDetails = ({
  /// Facebook's user identifier for this account.
  String userIdentifier,

  /// The user's email address.
  ///
  /// This may be null if the user hasn't granted email permission.
  String? email,

  /// The user's full name.
  String? fullName,

  /// The user's first name.
  String? firstName,

  /// The user's last name.
  String? lastName,

  /// The user's profile picture URL.
  Uri? image,
});

/// Result of a successful authentication using Facebook as identity provider.
typedef FacebookAuthSuccess = ({
  /// The ID of the `FacebookAccount` database entity.
  UuidValue facebookAccountId,

  /// The ID of the associated `AuthUser`.
  UuidValue authUserId,

  /// Details of the Facebook account.
  FacebookAccountDetails details,

  /// Whether the associated `AuthUser` was newly created during authentication.
  bool newAccount,

  /// The scopes granted to the associated `AuthUser`.
  Set<Scope> scopes,
});

/// Utility functions for the Facebook identity provider.
///
/// These functions can be used to compose custom authentication and
/// administration flows if needed.
///
/// But for most cases, the methods exposed by [FacebookIdp] and
/// [FacebookIdpAdmin] should be sufficient.
class FacebookIdpUtils {
  /// Configuration for the Facebook identity provider.
  final FacebookIdpConfig config;

  final AuthUsers _authUsers;

  /// Creates a new instance of [FacebookIdpUtils].
  FacebookIdpUtils({
    required this.config,
    required final TokenManager tokenManager,
    required final AuthUsers authUsers,
  }) : _authUsers = authUsers;

  /// Authenticates a user using a Facebook access token.
  ///
  /// This method verifies the token with Facebook's Debug Token API and fetches
  /// the user's profile information. If the Facebook user ID is not yet known
  /// in the system, a new `AuthUser` is created.
  Future<FacebookAuthSuccess> authenticate(
    final Session session, {
    required final String accessToken,
    required final Transaction? transaction,
  }) async {
    final accountDetails = await fetchAccountDetails(
      session,
      accessToken: accessToken,
    );

    var facebookAccount = await FacebookAccount.db.findFirstRow(
      session,
      where: (final t) => t.userIdentifier.equals(
        accountDetails.userIdentifier,
      ),
      transaction: transaction,
    );

    final createNewUser = facebookAccount == null;

    final AuthUserModel authUser = switch (createNewUser) {
      true => await _authUsers.create(
        session,
        transaction: transaction,
      ),
      false => await _authUsers.get(
        session,
        authUserId: facebookAccount!.authUserId,
        transaction: transaction,
      ),
    };

    if (createNewUser) {
      facebookAccount = await linkFacebookAuthentication(
        session,
        authUserId: authUser.id,
        accountDetails: accountDetails,
        accessToken: accessToken,
        transaction: transaction,
      );
    }

    // Execute custom callback if provided
    if (config.getExtraFacebookInfoCallback != null) {
      await config.getExtraFacebookInfoCallback!(
        session,
        accountDetails: accountDetails,
        accessToken: accessToken,
        transaction: transaction,
      );
    }

    return (
      facebookAccountId: facebookAccount.id!,
      authUserId: facebookAccount.authUserId,
      details: accountDetails,
      newAccount: createNewUser,
      scopes: authUser.scopes,
    );
  }

  /// Returns the account details for the given [accessToken].
  ///
  /// This method first verifies the token using Facebook's Debug Token API,
  /// then fetches the user's profile information from the Graph API.
  ///
  /// Reference: https://developers.facebook.com/docs/graph-api/reference/user
  Future<FacebookAccountDetails> fetchAccountDetails(
    final Session session, {
    required final String accessToken,
  }) async {
    // First, verify the access token
    await _verifyAccessToken(session, accessToken: accessToken);

    // Fetch user profile data from Graph API
    final response = await http.get(
      Uri.https(
        'graph.facebook.com',
        '/me',
        {
          'fields': 'id,name,first_name,last_name,email,picture.type(large)',
          'access_token': accessToken,
        },
      ),
    );

    if (response.statusCode != 200) {
      session.log(
        'Failed to fetch Facebook user data: ${response.statusCode} ${response.body}',
        level: LogLevel.error,
      );
      throw FacebookIdTokenVerificationException();
    }

    final Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      session.log(
        'Failed to parse Facebook user data response',
        level: LogLevel.error,
        exception: e,
        stackTrace: stackTrace,
      );
      throw FacebookIdTokenVerificationException();
    }

    final userIdentifier = data['id'] as String?;
    if (userIdentifier == null) {
      session.log(
        'Facebook user ID not found in response',
        level: LogLevel.error,
      );
      throw FacebookIdTokenVerificationException();
    }

    final accountDetails = (
      userIdentifier: userIdentifier,
      email: (data['email'] as String?)?.toLowerCase(),
      fullName: data['name'] as String?,
      firstName: data['first_name'] as String?,
      lastName: data['last_name'] as String?,
      image: _extractProfilePictureUrl(data),
    );

    // Validate account details
    config.facebookAccountDetailsValidation(accountDetails);

    return accountDetails;
  }

  /// Verifies a Facebook access token using the Debug Token API.
  ///
  /// Reference: https://developers.facebook.com/docs/graph-api/reference/debug_token
  Future<void> _verifyAccessToken(
    final Session session, {
    required final String accessToken,
  }) async {
    // Get app access token for verification
    final appAccessToken = '${config.appId}|${config.appSecret}';

    final response = await http.get(
      Uri.https(
        'graph.facebook.com',
        '/debug_token',
        {
          'input_token': accessToken,
          'access_token': appAccessToken,
        },
      ),
    );

    if (response.statusCode != 200) {
      session.log(
        'Failed to verify Facebook access token: ${response.statusCode}',
        level: LogLevel.error,
      );
      throw FacebookIdTokenVerificationException();
    }

    final Map<String, dynamic> responseData;
    try {
      responseData = json.decode(response.body) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      session.log(
        'Failed to parse Facebook token verification response',
        level: LogLevel.error,
        exception: e,
        stackTrace: stackTrace,
      );
      throw FacebookIdTokenVerificationException();
    }

    final data = responseData['data'] as Map<String, dynamic>?;
    if (data == null) {
      session.log(
        'Invalid Facebook token verification response format',
        level: LogLevel.error,
      );
      throw FacebookIdTokenVerificationException();
    }

    final isValid = data['is_valid'] as bool? ?? false;
    if (!isValid) {
      session.log(
        'Facebook access token is not valid',
        level: LogLevel.warning,
      );
      throw FacebookIdTokenVerificationException();
    }

    // Verify the token is for the correct app
    final appId = data['app_id'] as String?;
    if (appId != config.appId) {
      session.log(
        'Facebook access token is for a different app',
        level: LogLevel.warning,
      );
      throw FacebookIdTokenVerificationException();
    }

    // Check if token is expired
    final expiresAt = data['expires_at'] as int?;
    if (expiresAt != null && expiresAt > 0) {
      final expirationDate = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
      );
      if (DateTime.now().isAfter(expirationDate)) {
        session.log(
          'Facebook access token has expired',
          level: LogLevel.warning,
        );
        throw FacebookIdTokenVerificationException();
      }
    }
  }

  /// Extracts the profile picture URL from Facebook user data.
  ///
  /// Reference: https://developers.facebook.com/docs/graph-api/reference/user/picture
  Uri? _extractProfilePictureUrl(final Map<String, dynamic> data) {
    final picture = data['picture'] as Map<String, dynamic>?;
    if (picture == null) return null;

    final pictureData = picture['data'] as Map<String, dynamic>?;
    if (pictureData == null) return null;

    final pictureUrl = pictureData['url'] as String?;
    if (pictureUrl == null || pictureUrl.isEmpty) return null;

    return Uri.tryParse(pictureUrl);
  }

  /// Links a Facebook authentication to an existing [AuthUser].
  ///
  /// This creates a new [FacebookAccount] entity in the database.
  Future<FacebookAccount> linkFacebookAuthentication(
    final Session session, {
    required final UuidValue authUserId,
    required final FacebookAccountDetails accountDetails,
    required final String accessToken,
    required final Transaction? transaction,
  }) async {
    final facebookAccount = FacebookAccount(
      authUserId: authUserId,
      userIdentifier: accountDetails.userIdentifier,
      email: accountDetails.email,
      fullName: accountDetails.fullName,
      firstName: accountDetails.firstName,
      lastName: accountDetails.lastName,
    );

    return await FacebookAccount.db.insertRow(
      session,
      facebookAccount,
      transaction: transaction,
    );
  }
}
