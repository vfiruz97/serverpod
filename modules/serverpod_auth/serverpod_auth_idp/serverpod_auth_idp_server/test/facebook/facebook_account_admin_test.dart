import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';
import 'package:serverpod_auth_idp_server/providers/facebook.dart';
import 'package:test/test.dart';

import '../test_tools/serverpod_test_tools.dart';

void main() {
  final tokenManager = ServerSideSessionsTokenManager(
    config: ServerSideSessionsConfig(
      sessionKeyHashPepper: 'test-pepper',
    ),
  );

  withServerpod(
    'Given FacebookIdpAdmin,',
    (final sessionBuilder, final _) {
      late Session session;
      late FacebookIdpAdmin admin;
      late FacebookIdpUtils utils;
      late AuthUsers authUsers;

      setUp(() async {
        session = sessionBuilder.build();
        authUsers = const AuthUsers();

        const config = FacebookIdpConfig(
          clientCredentials: FacebookClientCredentials(
            appId: 'test-app-id',
            appSecret: 'test-app-secret',
          ),
        );

        utils = FacebookIdpUtils(
          config: config,
          tokenManager: tokenManager,
          authUsers: authUsers,
        );
        admin = FacebookIdpAdmin(
          utils: utils,
        );
      });

      test(
        'when calling `findUserByFacebookUserId` with existing Facebook user, then returns the auth user ID.',
        () async {
          final authUser = await authUsers.create(session);
          const facebookUserId = 'facebook-user-123';

          await FacebookAccount.db.insertRow(
            session,
            FacebookAccount(
              userIdentifier: facebookUserId,
              email: 'test@example.com',
              authUserId: authUser.id,
            ),
          );

          final result = await FacebookIdpAdmin.findUserByFacebookUserId(
            session,
            userIdentifier: facebookUserId,
          );

          expect(result, equals(authUser.id));
        },
      );

      test(
        'when calling `findUserByFacebookUserId` with non-existent user, then returns null.',
        () async {
          final result = await FacebookIdpAdmin.findUserByFacebookUserId(
            session,
            userIdentifier: 'non-existent-facebook-user',
          );

          expect(result, isNull);
        },
      );

      test(
        'when calling `linkFacebookAuthentication`, then creates a new FacebookAccount.',
        () async {
          final authUser = await authUsers.create(session);
          final accountDetails = (
            userIdentifier: 'facebook-user-456',
            email: 'newuser@example.com',
            fullName: 'New User',
            firstName: 'New',
            lastName: 'User',
            image: Uri.tryParse('https://example.com/image.jpg'),
          );

          final facebookAccount = await admin.linkFacebookAuthentication(
            session,
            authUserId: authUser.id,
            accountDetails: accountDetails,
          );

          expect(facebookAccount.authUserId, equals(authUser.id));
          expect(facebookAccount.userIdentifier, equals('facebook-user-456'));
          expect(facebookAccount.email, equals('newuser@example.com'));
          expect(facebookAccount.fullName, equals('New User'));
          expect(facebookAccount.firstName, equals('New'));
          expect(facebookAccount.lastName, equals('User'));
        },
      );

      test(
        'when linking Facebook authentication for different users, then creates two separate accounts.',
        () async {
          await FacebookAccount.db.deleteWhere(
            session,
            where: (final t) => Constant.bool(true),
          );

          final authUser1 = await authUsers.create(session);
          final authUser2 = await authUsers.create(session);

          const accountDetails1 = (
            userIdentifier: 'facebook-user-789',
            email: 'user1@example.com',
            fullName: 'User One',
            firstName: 'User',
            lastName: 'One',
            image: null,
          );

          const accountDetails2 = (
            userIdentifier: 'facebook-user-790',
            email: 'user2@example.com',
            fullName: 'User Two',
            firstName: 'User',
            lastName: 'Two',
            image: null,
          );

          await admin.linkFacebookAuthentication(
            session,
            authUserId: authUser1.id,
            accountDetails: accountDetails1,
          );

          await admin.linkFacebookAuthentication(
            session,
            authUserId: authUser2.id,
            accountDetails: accountDetails2,
          );

          final accounts = await FacebookAccount.db.find(session);
          expect(accounts.length, equals(2));
        },
      );
    },
  );
}
