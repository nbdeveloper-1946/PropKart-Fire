import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bcrypt/bcrypt.dart';
import '../../../core/utils/logger.dart';

class UsersService {
  Future<Map<String, dynamic>> getUsers({
    String? search,
    String? roleId,
    String? status,
  }) async {
    try {
      BeautifulLogger.sync("Fetching users directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("users");

      // Filter out deleted by default
      query = query.where("deleted_at", isNull: true);

      if (roleId != null && roleId.isNotEmpty) {
        query = query.where("role_id", isEqualTo: roleId);
      }
      if (status != null && status != 'All') {
        final bool isActive = status == 'Active';
        query = query.where("is_active", isEqualTo: isActive);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> usersList = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        
        // Resolve role name
        final userRoleId = data['role_id'] as String?;
        String roleName = "Sales";
        if (userRoleId != null && userRoleId.isNotEmpty) {
          final roleDoc = await FirebaseFirestore.instance.collection("roles").doc(userRoleId).get();
          if (roleDoc.exists) {
            roleName = roleDoc.data()?['name'] as String? ?? "Sales";
          }
        }

        final map = {
          ...data,
          'id': id,
          'role': {
            'id': userRoleId,
            'name': roleName,
          },
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        if (search != null && search.isNotEmpty) {
          final name = map['full_name']?.toString().toLowerCase() ?? '';
          final email = map['email']?.toString().toLowerCase() ?? '';
          final mobile = map['mobile']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!name.contains(cleanSearch) && !email.contains(cleanSearch) && !mobile.contains(cleanSearch)) {
            continue;
          }
        }

        usersList.add(map);
      }

      return {
        "success": true,
        "data": {
          "users": usersList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore users", e);
      return {"success": false, "data": {"users": []}};
    }
  }

  Future<Map<String, dynamic>> getRoles() async {
    try {
      BeautifulLogger.sync("Fetching roles directly from Firestore...");
      final snapshot = await FirebaseFirestore.instance.collection("roles").get();
      final List<Map<String, dynamic>> rolesList = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        rolesList.add({
          'id': doc.id,
          'name': data['name'] ?? 'N/A',
        });
      }

      return {
        "success": true,
        "data": {
          "roles": rolesList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore roles", e);
      return {"success": false, "data": {"roles": []}};
    }
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    try {
      final docId = userData['id'] ?? FirebaseFirestore.instance.collection('users').doc().id;
      final data = {
        ...userData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      // Hash password client-side before writing to Firestore
      if (userData['password'] != null) {
        final pass = userData['password'] as String;
        data['password_hash'] = BCrypt.hashpw(pass, BCrypt.gensalt());
        data.remove('password');
      }

      await FirebaseFirestore.instance.collection('users').doc(docId).set(data);
      return {
        "success": true,
        "data": {"user": data}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create user in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateUser(String id, Map<String, dynamic> userData) async {
    try {
      final updateData = {
        ...userData,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Hash password client-side if updated
      if (userData['password'] != null) {
        final pass = userData['password'] as String;
        updateData['password_hash'] = BCrypt.hashpw(pass, BCrypt.gensalt());
        updateData.remove('password');
      }

      await FirebaseFirestore.instance.collection('users').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      return {
        "success": true,
        "data": {
          "user": {
            ...?doc.data(),
            'id': id,
          }
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update user in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> toggleUserStatus(String id, bool isActive) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to toggle user status in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteUser(String id) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete user in Firestore", e);
      rethrow;
    }
  }
}
