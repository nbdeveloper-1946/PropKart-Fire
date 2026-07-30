import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/storage/repository_coordinator.dart';
import '../../../core/utils/logger.dart';

class RequirementsService {
  final RepositoryCoordinator _coordinator = RepositoryCoordinator();

  Future<Map<String, dynamic>> _hydrateRequirement(Map<String, dynamic> r) async {
    final enriched = Map<String, dynamic>.from(r);

    Future<String> getName(String category, String? id) async {
      if (id == null || id.isEmpty) return 'N/A';
      try {
        final list = await _coordinator.lookupLocal.getLookupsByCategory(category);
        for (final item in list) {
          if (item.id == id) return item.name;
        }
      } catch (_) {}
      return 'N/A';
    }

    enriched['category'] = {'name': await getName('property_category', r['category_id'])};
    enriched['property_type'] = {'name': await getName('property_type', r['property_type_id'])};
    enriched['configuration'] = {'name': await getName('configuration', r['configuration_id'])};
    enriched['listing_type'] = {'name': await getName('listing_type', r['listing_type_id'])};
    enriched['city'] = {'city_name': await getName('city', r['city_id'])};

    // Hydrate requirement_areas list
    final List<dynamic> areaIds = r['area_ids'] ?? [];
    final List<Map<String, dynamic>> areasList = [];
    for (final aId in areaIds) {
      final name = await getName('area', aId);
      areasList.add({
        'area': {'id': aId, 'area_name': name}
      });
    }
    enriched['requirement_areas'] = areasList;

    return enriched;
  }

  Future<Map<String, dynamic>> getRequirements({
    String? search,
    String? configurationId,
    String? propertyTypeId,
    String? status,
    String? listingTypeId,
    bool? includeDeleted,
  }) async {
    try {
      BeautifulLogger.sync("Fetching requirements directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("requirements");

      // Filter out deleted by default
      if (includeDeleted != true) {
        query = query.where("deleted_at", isNull: true);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> requirementsList = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // In-memory filters to avoid composite index requirements
        if (configurationId != null && configurationId.isNotEmpty && data['configuration_id'] != configurationId) continue;
        if (propertyTypeId != null && propertyTypeId.isNotEmpty && data['property_type_id'] != propertyTypeId) continue;
        if (status != null && status != 'All' && data['status'] != status) continue;
        if (listingTypeId != null && listingTypeId.isNotEmpty && data['listing_type_id'] != listingTypeId) continue;
        
        final id = doc.id;
        final map = {
          ...data,
          'id': id,
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        // Apply search filter locally to avoid complex Firestore indexes
        if (search != null && search.isNotEmpty) {
          final clientName = map['client_name']?.toString().toLowerCase() ?? '';
          final clientMobile = map['client_mobile']?.toString().toLowerCase() ?? '';
          final remarks = map['remarks']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!clientName.contains(cleanSearch) && !clientMobile.contains(cleanSearch) && !remarks.contains(cleanSearch)) {
            continue;
          }
        }

        requirementsList.add(await _hydrateRequirement(map));
      }

      return {
        "success": true,
        "data": {
          "requirements": requirementsList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore requirements", e);
      return {"success": false, "data": {"requirements": []}};
    }
  }

  Future<Map<String, dynamic>> createRequirement(Map<String, dynamic> requirementData) async {
    try {
      final docId = requirementData['id'] ?? FirebaseFirestore.instance.collection('requirements').doc().id;
      final data = {
        ...requirementData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      await FirebaseFirestore.instance.collection('requirements').doc(docId).set(data);
      final hydrated = await _hydrateRequirement(data);
      return {
        "success": true,
        "data": {"requirement": hydrated}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create requirement in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateRequirement(String id, Map<String, dynamic> requirementData) async {
    try {
      final updateData = {
        ...requirementData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await FirebaseFirestore.instance.collection('requirements').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('requirements').doc(id).get();
      final hydrated = await _hydrateRequirement({
        ...?doc.data(),
        'id': id,
      });

      return {
        "success": true,
        "data": {"requirement": hydrated}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update requirement in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteRequirement(String id) async {
    try {
      await FirebaseFirestore.instance.collection('requirements').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete requirement in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getBinRequirements() async {
    return getRequirements(includeDeleted: true);
  }

  Future<Map<String, dynamic>> restoreRequirement(String id) async {
    try {
      await FirebaseFirestore.instance.collection('requirements').doc(id).update({
        'deleted_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to restore requirement in Firestore", e);
      rethrow;
    }
  }

  Future<void> permanentDeleteRequirement(String id) async {
    await FirebaseFirestore.instance.collection('requirements').doc(id).delete();
  }

  Future<void> emptyBin() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('requirements')
        .where('deleted_at', isNull: false)
        .get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
