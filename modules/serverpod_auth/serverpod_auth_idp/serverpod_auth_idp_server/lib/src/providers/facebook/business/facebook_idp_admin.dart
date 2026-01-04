import 'package:serverpod/serverpod.dart';

import '../../../generated/protocol.dart';
import 'facebook_idp_utils.dart';

/// Collection of Facebook-account admin methods.
///
/// These methods can be used to manage Facebook accounts and perform
/// administrative operations.
class FacebookIdpAdmin {
  /// Utility functions for the Facebook identity provider.
  final FacebookIdpUtils utils;

  /// Creates a new instance of [FacebookIdpAdmin].
  const FacebookIdpAdmin({required this.utils});

  /// Returns the account details for the given [accessToken].
  ///
  /// This method verifies the token and fetches the user's profile information
  /// from Facebook's Graph API.
  ///
  /// Reference: https://developers.facebook.com/docs/graph-api/reference/user
  Future<FacebookAccountDetails> fetchAccountDetails(
    final Session session, {
    required final String accessToken,
  }) async {
    return utils.fetchAccountDetails(
      session,
      accessToken: accessToken,
    );
  }

  /// Adds a Facebook authentication to the given [authUserId].
  ///
  /// Returns the newly created Facebook account.
  Future<FacebookAccount> linkFacebookAuthentication(
    final Session session, {
    required final UuidValue authUserId,
    required final FacebookAccountDetails accountDetails,
    required final String accessToken,
    final Transaction? transaction,
  }) async {
    return utils.linkFacebookAuthentication(
      session,
      authUserId: authUserId,
      accountDetails: accountDetails,
      accessToken: accessToken,
      transaction: transaction,
    );
  }

  /// Return the `AuthUser` id for the Facebook user id, if any.
  static Future<UuidValue?> findUserByFacebookUserId(
    final Session session, {
    required final String userIdentifier,
    final Transaction? transaction,
  }) async {
    final account = await FacebookAccount.db.findFirstRow(
      session,
      where: (final t) => t.userIdentifier.equals(userIdentifier),
      transaction: transaction,
    );
    return account?.authUserId;
  }
}
