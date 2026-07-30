import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/logger.dart';

class ClientsService {
  Future<Map<String, dynamic>> getClients({String? search, String? stage, String? source}) async {
    try {
      BeautifulLogger.sync("Fetching clients directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("clients");

      // Filter out deleted by default
      query = query.where("deleted_at", isNull: true);

      if (stage != null && stage != 'All') {
        query = query.where("stage", isEqualTo: stage);
      }
      if (source != null && source != 'All') {
        query = query.where("source", isEqualTo: source);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> clientsList = [];

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
          final mobile = map['mobile']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!name.contains(cleanSearch) && !mobile.contains(cleanSearch)) {
            continue;
          }
        }

        clientsList.add(map);
      }

      return {
        "success": true,
        "data": {
          "clients": clientsList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore clients", e);
      return {"success": false, "data": {"clients": []}};
    }
  }

  Future<Map<String, dynamic>> createClient(Map<String, dynamic> clientData) async {
    try {
      final docId = clientData['id'] ?? FirebaseFirestore.instance.collection('clients').doc().id;
      final data = {
        ...clientData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      await FirebaseFirestore.instance.collection('clients').doc(docId).set(data);
      return {
        "success": true,
        "data": {"client": data}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create client in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateClient(String id, Map<String, dynamic> clientData) async {
    try {
      final updateData = {
        ...clientData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await FirebaseFirestore.instance.collection('clients').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('clients').doc(id).get();
      return {
        "success": true,
        "data": {
          "client": {
            ...?doc.data(),
            'id': id,
          }
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update client in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteClient(String id) async {
    try {
      await FirebaseFirestore.instance.collection('clients').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete client in Firestore", e);
      rethrow;
    }
  }
}
