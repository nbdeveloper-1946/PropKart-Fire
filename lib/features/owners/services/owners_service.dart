import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/logger.dart';

class OwnersService {
  Future<Map<String, dynamic>> getOwners({String? search}) async {
    try {
      BeautifulLogger.sync("Fetching owners directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("owners");

      // Filter out deleted by default
      query = query.where("deleted_at", isNull: true);

      final snapshot = await query.get();
      final List<Map<String, dynamic>> ownersList = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        final map = {
          ...data,
          'id': id,
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        if (search != null && search.isNotEmpty) {
          final name = map['name']?.toString().toLowerCase() ?? '';
          final contact = map['mobile']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!name.contains(cleanSearch) && !contact.contains(cleanSearch)) {
            continue;
          }
        }

        ownersList.add(map);
      }

      return {
        "success": true,
        "data": {
          "owners": ownersList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore owners", e);
      return {"success": false, "data": {"owners": []}};
    }
  }

  Future<Map<String, dynamic>> createOwner(Map<String, dynamic> ownerData) async {
    try {
      final docId = ownerData['id'] ?? FirebaseFirestore.instance.collection('owners').doc().id;
      final data = {
        ...ownerData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      await FirebaseFirestore.instance.collection('owners').doc(docId).set(data);
      return {
        "success": true,
        "data": {"owner": data}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create owner in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateOwner(String id, Map<String, dynamic> ownerData) async {
    try {
      final updateData = {
        ...ownerData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await FirebaseFirestore.instance.collection('owners').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('owners').doc(id).get();
      return {
        "success": true,
        "data": {
          "owner": {
            ...?doc.data(),
            'id': id,
          }
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update owner in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteOwner(String id) async {
    try {
      await FirebaseFirestore.instance.collection('owners').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete owner in Firestore", e);
      rethrow;
    }
  }
}
