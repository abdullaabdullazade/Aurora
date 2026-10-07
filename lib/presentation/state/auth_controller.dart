import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/config/app_config.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.userChanges();
});

class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConfig.googleWebClientId.isNotEmpty
        ? AppConfig.googleWebClientId
        : null,
  );

  Future<User?> signInWithGoogle() async {
    // Without AURORA_GOOGLE_WEB_CLIENT_ID google_sign_in falls back to the
    // default_web_client_id generated from google-services.json.
    var googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    var googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      // Stale Play Services session after logout can yield an empty idToken.
      await _clearGoogleSession();
      googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      googleAuth = await googleUser.authentication;
    }

    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token. Check the Web client ID '
            'in Firebase / Google Cloud.',
      );
    }

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    final googleProfile = userCredential.additionalUserInfo?.profile;
    final profilePhoto = googleProfile?['picture'];
    final profileName = googleProfile?['name'];
    final googlePhoto =
        googleUser.photoUrl ?? (profilePhoto is String ? profilePhoto : null);
    final googleName =
        googleUser.displayName ?? (profileName is String ? profileName : null);

    if ((user.photoURL == null || user.photoURL!.isEmpty) &&
        googlePhoto != null &&
        googlePhoto.isNotEmpty) {
      await user.updatePhotoURL(googlePhoto);
    }
    if ((user.displayName == null || user.displayName!.isEmpty) &&
        googleName != null &&
        googleName.isNotEmpty) {
      await user.updateDisplayName(googleName);
    }
    await user.reload();
    return _auth.currentUser;
  }

  Future<void> signOut() async {
    await _clearGoogleSession();
    await _auth.signOut();
  }

  Future<void> _clearGoogleSession() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  /// Returns a Google access token with [AppConfig.youtubeReadonlyScope], or
  /// null when the user is signed out or declined the extra permission.
  Future<String?> youtubeAccessToken() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    if (account == null) return null;

    final granted = await _googleSignIn.requestScopes(
      [AppConfig.youtubeReadonlyScope],
    );
    if (!granted) return null;

    account = _googleSignIn.currentUser ?? account;
    final auth = await account.authentication;
    return auth.accessToken;
  }
}

final authControllerProvider = Provider((ref) => AuthController());
