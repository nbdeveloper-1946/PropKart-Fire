import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/logger.dart';

class BuildersService {
  Future<Map<String, dynamic>> getBuilders({String? search, String? tier}) async {
    try {
      BeautifulLogger.sync("Fetching builders directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("builders");

      // Filter out deleted by default
      query = query.where("deleted_at", isNull: true);

      if (tier != null && tier != 'All') {
        query = query.where("tier", isEqualTo: tier);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> buildersList = [];

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
          final contact = map['contact_person']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!name.contains(cleanSearch) && !contact.contains(cleanSearch)) {
            continue;
          }
        }

        buildersList.add(map);
      }

      return {
        "success": true,
        "data": {
          "builders": buildersList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore builders", e);
      return {"success": false, "data": {"builders": []}};
    }
  }

  Future<Map<String, dynamic>> createBuilder(Map<String, dynamic> builderData) async {
    try {
      final docId = builderData['id'] ?? FirebaseFirestore.instance.collection('builders').doc().id;
      final data = {
        ...builderData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      await FirebaseFirestore.instance.collection('builders').doc(docId).set(data);
      return {
        "success": true,
        "data": {"builder": data}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create builder in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateBuilder(String id, Map<String, dynamic> builderData) async {
    try {
      final updateData = {
        ...builderData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await FirebaseFirestore.instance.collection('builders').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('builders').doc(id).get();
      return {
        "success": true,
        "data": {
          "builder": {
            ...?doc.data(),
            'id': id,
          }
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update builder in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteBuilder(String id) async {
    try {
      await FirebaseFirestore.instance.collection('builders').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete builder in Firestore", e);
      rethrow;
    }
  }
}
