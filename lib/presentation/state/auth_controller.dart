import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  // userChanges also emits profile updates (photo/display name), while
  // authStateChanges only guarantees sign-in/sign-out events.
  return FirebaseAuth.instance.userChanges();
});

class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

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

    // Firebase normally copies these fields from Google, but existing users
    // can keep an empty profile. Persist them explicitly so every screen and
    // future app launch sees the same avatar.
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
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

final authControllerProvider = Provider((ref) => AuthController());
