import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? verificationId;
  User? user;
  bool isLoading = false;
  String? errorMessage;

  AuthService() {
    try {
      _auth.authStateChanges().listen((User? u) {
        user = u;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('AuthService: Firebase not ready - $e');
    }
  }

  Future<void> sendOTP(String phoneNumber) async {
    isLoading = true;
    errorMessage = null;
    verificationId = null;
    notifyListeners();

    final completer = Completer<void>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Keep Firebase default behavior; test mode usually uses manual OTP entry.
          debugPrint('AuthService: verificationCompleted triggered.');
          try {
            await _auth.signInWithCredential(credential);
            await saveUserToFirestore();
            debugPrint('AuthService: Auto sign-in success.');
          } catch (e) {
            debugPrint('AuthService: Auto sign-in failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          errorMessage = e.message ?? 'Phone verification failed.';
          debugPrint('AuthService: verifyPhoneNumber failed: ${e.code} - ${e.message}');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        },
        codeSent: (String verId, int? resendToken) {
          verificationId = verId;
          debugPrint('AuthService: codeSent, verificationId=$verId');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        codeAutoRetrievalTimeout: (String verId) {
          verificationId = verId;
          debugPrint('AuthService: autoRetrievalTimeout, verificationId=$verId');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      // Wait until either codeSent/timeout or verificationFailed callback completes.
      await completer.future.timeout(const Duration(seconds: 30));
    } on FirebaseAuthException catch (e) {
      errorMessage = e.message ?? 'Failed to send OTP.';
      rethrow;
    } catch (e) {
      errorMessage = 'Failed to send OTP.';
      debugPrint('AuthService: sendOTP unexpected error: $e');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOTP(String otp) async {
    if (verificationId == null) {
      errorMessage = 'Verification session expired. Please request OTP again.';
      notifyListeners();
      debugPrint('AuthService: verifyOTP failed, verificationId is null.');
      return false;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId!,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      await saveUserToFirestore();
      debugPrint('AuthService: OTP verify success.');
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = e.message ?? 'Invalid OTP. Please try again.';
      debugPrint('AuthService: OTP verify failed: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      errorMessage = 'OTP verification failed. Please try again.';
      debugPrint('AuthService: OTP verification error: $e');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveUserToFirestore({String name = 'New User'}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final uid = currentUser.uid;
    final phone = currentUser.phoneNumber ?? '';

    final docRef = _firestore.collection('users').doc(uid);
    final snapshot = await docRef.get();

    // Enforce your required user schema.
    final payload = <String, dynamic>{
      'uid': uid,
      'phone': phone,
      'name': name,
      'language': 'Telugu',
      'onlineStatus': true,
    };

    if (!snapshot.exists) {
      await docRef.set(payload);
      return;
    }

    // Keep existing name if it was set earlier; still update required fields.
    final existing = snapshot.data() ?? const <String, dynamic>{};
    await docRef.set(
      <String, dynamic>{
        ...payload,
        'name': existing['name'] ?? name,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> logout() async {
    await setOnlineStatus(false);
    await _auth.signOut();
  }

  Future<void> setOnlineStatus(bool status) async {
    if (_auth.currentUser != null) {
      final uid = _auth.currentUser!.uid;
      await _firestore.collection('users').doc(uid).set(
        {'onlineStatus': status},
        SetOptions(merge: true),
      );
    }
  }
}
