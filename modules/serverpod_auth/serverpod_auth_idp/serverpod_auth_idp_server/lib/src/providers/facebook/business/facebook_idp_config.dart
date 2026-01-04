import 'package:serverpod/serverpod.dart';

import '../../../../../core.dart';
import '../../../utils/get_passwords_extension.dart';
import 'facebook_idp.dart';
import 'facebook_idp_utils.dart';

/// Function to be called to check whether a Facebook account details match the
/// requirements during registration.
typedef FacebookAccountDetailsValidation =
    void Function(
      FacebookAccountDetails accountDetails,
    );

/// Function to be called to extract additional information from Facebook Graph API
/// using the access token. The [session] and [transaction] can be used to
/// store additional information in the database.
typedef GetExtraFacebookInfoCallback =
    Future<void> Function(
      Session session, {
      required FacebookAccountDetails accountDetails,
      required String accessToken,
      required Transaction? transaction,
    });

/// Configuration for the Facebook identity provider.
///
/// This class holds the necessary credentials and settings for Facebook authentication.
/// To set up Facebook Login, you need to create a Facebook App in the Facebook Developer Console.
///
/// Reference: https://developers.facebook.com/docs/development/create-an-app/
class FacebookIdpConfig extends IdentityProviderBuilder<FacebookIdp> {
  /// The Facebook App ID.
  ///
  /// This is the unique identifier for your Facebook App.
  /// You can find it in the Facebook Developer Console.
  final String appId;

  /// The Facebook App Secret.
  ///
  /// This is a secret key used to verify requests from Facebook.
  /// Keep this value secure and never expose it in client-side code.
  /// You can find it in the Facebook Developer Console.
  final String appSecret;

  /// Validation function for Facebook account details.
  ///
  /// This function should throw an exception if the account details do not
  /// match the requirements. If the function returns normally, the account
  /// is considered valid.
  ///
  /// It can be used to enforce additional requirements on the Facebook account
  /// details before allowing the user to sign in.
  ///
  /// To avoid blocking real users, adjust your validation function with care.
  final FacebookAccountDetailsValidation facebookAccountDetailsValidation;

  /// Callback that can be used with the access token to extract additional
  /// information from Facebook Graph API.
  ///
  /// This can be used to fetch additional user data or perform additional
  /// verification steps.
  final GetExtraFacebookInfoCallback? getExtraFacebookInfoCallback;

  /// Creates a new instance of [FacebookIdpConfig].
  const FacebookIdpConfig({
    required this.appId,
    required this.appSecret,
    this.facebookAccountDetailsValidation = validateFacebookAccountDetails,
    this.getExtraFacebookInfoCallback,
  });

  /// Default validation function for extracted Facebook account details.
  ///
  /// This default implementation performs minimal validation.
  /// Override this to add custom validation logic.
  static void validateFacebookAccountDetails(
    final FacebookAccountDetails accountDetails,
  ) {
    // Default validation - can be customized by users
    if (accountDetails.userIdentifier.isEmpty) {
      throw FacebookUserInfoMissingDataException();
    }
  }

  @override
  FacebookIdp build({
    required final TokenManager tokenManager,
    required final AuthUsers authUsers,
    required final UserProfiles userProfiles,
  }) {
    return FacebookIdp(
      this,
      tokenManager: tokenManager,
      authUsers: authUsers,
      userProfiles: userProfiles,
    );
  }
}

/// Creates a new [FacebookIdpConfig] from keys on the `passwords.yaml` file.
///
/// This constructor requires that a [Serverpod] instance has already been initialized.
///
/// Expected format in passwords.yaml:
/// ```yaml
/// facebookAppId: 'your-app-id'
/// facebookAppSecret: 'your-app-secret'
/// ```
class FacebookIdpConfigFromPasswords extends FacebookIdpConfig {
  /// Creates a new [FacebookIdpConfigFromPasswords] instance.
  FacebookIdpConfigFromPasswords()
    : super(
        appId: Serverpod.instance.getPasswordOrThrow('facebookAppId'),
        appSecret: Serverpod.instance.getPasswordOrThrow('facebookAppSecret'),
      );
}

/// Exception thrown when Facebook user information is missing required data.
class FacebookUserInfoMissingDataException implements Exception {
  @override
  String toString() =>
      'FacebookUserInfoMissingDataException: Required user information is missing from Facebook account.';
}
