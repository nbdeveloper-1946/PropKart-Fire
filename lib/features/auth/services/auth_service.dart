import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:bcrypt/bcrypt.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/logger.dart';

class AuthService {
  final SecureStorage _secureStorage = SecureStorage();

  // Static role permissions map derived from the original permissions.js
  static const List<String> _commonPermissions = [
    "users.upload_self_photo",
    "properties.read",
    "properties.create",
    "properties.update",
    "requirements.read",
    "requirements.create",
    "requirements.update",
    "owners.read",
    "owners.create",
    "owners.update",
    "clients.read",
    "clients.create",
    "clients.update",
    "search.read",
    "share.create",
    "share.read",
    "share.revoke",
    "followups.read",
    "followups.write",
    "site_visits.read",
    "site_visits.write",
    "notifications.read",
    "checklist.read",
    "checklist.write",
    "places.read",
    "dashboard.read",
    "builders.read",
    "legal.read",
    "legal.write",
  ];

  static const List<String> _adminExtra = [
    "users.read",
    "users.create",
    "users.update",
    "users.delete",
    "properties.delete",
    "properties.verify",
    "requirements.delete",
    "owners.delete",
    "clients.delete",
    "lookup.manage",
    "audit.read",
  ];

  static const List<String> _superExtra = [
    "users.manage_admins",
    "config.manage",
    "health.detailed",
  ];

  static List<String> getPermissionsForRole(String roleName) {
    if (roleName == "Super Admin") {
      return [..._commonPermissions, ..._adminExtra, ..._superExtra];
    } else if (roleName == "Admin") {
      return [..._commonPermissions, ..._adminExtra];
    } else {
      // Sales
      final sales = _commonPermissions
          .where((p) => !["owners.delete", "clients.delete"].contains(p))
          .toList();
      sales.addAll(["properties.delete", "requirements.delete"]);
      return sales;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password, {bool rememberMe = false}) async {
    try {
      BeautifulLogger.sync("Authenticating user $email directly against Firestore...");
      
      // 1. Query users collection
      final userSnapshot = await FirebaseFirestore.instance
          .collection("users")
          .where("email", isEqualTo: email.trim().toLowerCase())
          .get();

      if (userSnapshot.docs.isEmpty) {
        throw Exception("Invalid email or password.");
      }

      final doc = userSnapshot.docs.first;
      final userData = doc.data();

      if (userData['is_active'] != true || userData['deleted_at'] != null) {
        throw Exception("This account is inactive or deleted.");
      }

      // 2. Verify password hash using bcrypt
      final passwordHash = userData['password_hash'] as String?;
      if (passwordHash == null || !BCrypt.checkpw(password, passwordHash)) {
        throw Exception("Invalid email or password.");
      }

      // 3. Resolve role name
      final roleId = userData['role_id'] as String?;
      String roleName = "Sales";
      if (roleId != null && roleId.isNotEmpty) {
        final roleDoc = await FirebaseFirestore.instance.collection("roles").doc(roleId).get();
        if (roleDoc.exists) {
          roleName = roleDoc.data()?['name'] as String? ?? "Sales";
        }
      }

      // 4. Get permissions
      final permissions = getPermissionsForRole(roleName);

      // Save user ID to secure storage so getProfile can retrieve it
      final userId = doc.id;
      await _secureStorage.saveToken(userId, persist: rememberMe);

      // Try Firebase Auth login/create behind the scenes to keep Auth SDK in sync
      try {
        await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(),
          password: password,
        );
      } catch (_) {
        // If account isn't in Firebase Auth yet, sign up to sync them
        try {
          await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email.trim().toLowerCase(),
            password: password,
          );
        } catch (_) {}
      }

      // Construct standard response
      final userPayload = {
        "id": userId,
        "email": userData['email'],
        "full_name": userData['full_name'],
        "profile_photo": userData['profile_photo'],
        "mobile": userData['mobile'],
        "role": roleName,
        "permissions": permissions,
        "is_active": userData['is_active'],
        "admin_id": userData['admin_id'],
        "organization_id": userData['organization_id'],
      };

      return {
        "success": true,
        "message": "Login successful.",
        "data": {
          "user": userPayload,
          "token": userId,
          "refreshToken": "refresh-$userId",
        }
      };
    } catch (e) {
      BeautifulLogger.error("Login failed", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> refresh(String? refreshToken) async {
    // Return standard success mock response
    final userId = await _secureStorage.getToken() ?? "guest";
    return {
      "success": true,
      "data": {
        "token": userId,
        "refreshToken": "refresh-$userId",
      }
    };
  }

  Future<void> logout({String? refreshToken}) async {
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await _secureStorage.deleteToken();
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final userId = await _secureStorage.getToken();
      if (userId == null || userId.isEmpty) {
        throw Exception("Unauthenticated");
      }

      final doc = await FirebaseFirestore.instance.collection("users").doc(userId).get();
      if (!doc.exists) {
        throw Exception("User profile not found.");
      }

      final userData = doc.data()!;
      final roleId = userData['role_id'] as String?;
      String roleName = "Sales";
      if (roleId != null && roleId.isNotEmpty) {
        final roleDoc = await FirebaseFirestore.instance.collection("roles").doc(roleId).get();
        if (roleDoc.exists) {
          roleName = roleDoc.data()?['name'] as String? ?? "Sales";
        }
      }

      final permissions = getPermissionsForRole(roleName);

      final userPayload = {
        "id": userId,
        "email": userData['email'],
        "full_name": userData['full_name'],
        "profile_photo": userData['profile_photo'],
        "mobile": userData['mobile'],
        "role": roleName,
        "permissions": permissions,
        "is_active": userData['is_active'],
        "admin_id": userData['admin_id'],
        "organization_id": userData['organization_id'],
      };

      return {
        "success": true,
        "data": {
          "user": userPayload,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Get profile failed", e);
      rethrow;
    }
  }
}
