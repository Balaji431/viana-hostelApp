import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../app_logger.dart';

class FirebaseAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '907286443175-1uqe7brjctqhvoprujjv1ilf85ahongj.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  /// Current Firebase User
  static User? get currentUser => _auth.currentUser;

  /// Auth State Changes Stream
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 1. Register with Email and Password
  static Future<UserCredential?> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Save User Details in Firestore
        await _saveUserToFirestore(
          uid: credential.user!.uid,
          email: email,
          name: name,
          role: role,
        );
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      AppLogger.error("Firebase Sign Up Error: ${e.message}");
      rethrow;
    }
  }

  /// 2. Sign In with Email and Password
  static Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      AppLogger.error("Firebase Sign In Error: ${e.message}");
      rethrow;
    }
  }

  /// 3. Google Sign-In (Cross-platform iOS, Android, Web)
  static Future<UserCredential?> signInWithGoogle({String role = 'student'}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // Canceled by user

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        // Save/Update User Info in Firestore
        await _saveUserToFirestore(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email ?? '',
          name: userCredential.user!.displayName ?? 'User',
          role: role,
          photoUrl: userCredential.user!.photoURL,
        );
      }
      return userCredential;
    } catch (e) {
      AppLogger.error("Google Sign-In Error: $e");
      rethrow;
    }
  }

  /// 4. Sign Out
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      AppLogger.error("Sign Out Error: $e");
    }
  }

  /// 5. Password Reset Email
  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      AppLogger.error("Password Reset Error: $e");
      rethrow;
    }
  }

  /// Helper to persist User record in Firestore Database
  static Future<void> _saveUserToFirestore({
    required String uid,
    required String email,
    required String name,
    required String role,
    String? photoUrl,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final userDoc = await userRef.get();

    final data = {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role,
      'photoUrl': photoUrl ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!userDoc.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await userRef.set(data);
    } else {
      await userRef.update(data);
    }
  }

  /// Fetch User Profile Data from Firestore
  static Future<DocumentSnapshot<Map<String, dynamic>>?> getUserProfile(String uid) async {
    try {
      return await _db.collection('users').doc(uid).get();
    } catch (e) {
      AppLogger.error("Get User Profile Error: $e");
      return null;
    }
  }
}
