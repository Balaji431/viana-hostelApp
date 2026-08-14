import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with Email and Password
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuth signIn error: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("FirebaseAuth signIn error: $e");
      rethrow;
    }
  }

  /// Register new user with Email and Password
  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName);
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuth register error: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("FirebaseAuth register error: $e");
      rethrow;
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Firestore Collection helper
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _firestore.collection(path);
  }

  /// Firestore Document helper
  DocumentReference<Map<String, dynamic>> doc(String path) {
    return _firestore.doc(path);
  }
}
