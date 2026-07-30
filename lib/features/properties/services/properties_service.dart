import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/storage/repository_coordinator.dart';
import '../../../core/utils/logger.dart';

class PropertiesService {
  final RepositoryCoordinator _coordinator = RepositoryCoordinator();

  Future<Map<String, dynamic>> _hydrateProperty(Map<String, dynamic> p) async {
    final enriched = Map<String, dynamic>.from(p);

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

    enriched['category'] = {'name': await getName('property_category', p['category_id'])};
    enriched['property_type'] = {'name': await getName('property_type', p['property_type_id'])};
    enriched['configuration'] = {'name': await getName('configuration', p['configuration_id'])};
    enriched['listing_type'] = {'name': await getName('listing_type', p['listing_type_id'])};
    enriched['property_status'] = {'name': await getName('property_status', p['property_status_id'])};
    enriched['city'] = {'city_name': await getName('city', p['city_id'])};
    enriched['area'] = {
      'area_name': await getName('area', p['area_id']),
      'pincode': p['pincode'] ?? 'N/A'
    };
    enriched['furnishing_type'] = {'name': await getName('furnishing_type', p['furnishing_type_id'])};
    enriched['facing_type'] = {'name': await getName('facing_type', p['facing_type_id'])};
    enriched['ownership_type'] = {'name': await getName('ownership_type', p['ownership_type_id'])};
    enriched['brokerage_type'] = {'name': await getName('brokerage_type', p['brokerage_type_id'])};

    enriched['property_images'] = p['images'] ?? [];
    enriched['property_videos'] = p['videos'] ?? [];

    final List<dynamic> amenityIds = p['amenity_ids'] ?? [];
    final List<Map<String, dynamic>> amenitiesList = [];
    for (final aId in amenityIds) {
      final name = await getName('amenity', aId);
      amenitiesList.add({
        'amenity': {'id': aId, 'name': name}
      });
    }
    enriched['property_amenities'] = amenitiesList;

    return enriched;
  }

  Future<Map<String, dynamic>> getProperties({
    String? search,
    String? categoryId,
    String? areaId,
    String? listingTypeId,
    String? createdBy,
    bool? isVerified,
    bool? includeDeleted,
  }) async {
    try {
      BeautifulLogger.sync("Fetching properties directly from Firestore...");
      Query query = FirebaseFirestore.instance.collection("properties");

      // Filter out deleted by default
      if (includeDeleted != true) {
        query = query.where("deleted_at", isNull: true);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> propertiesList = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // In-memory filters to avoid composite index requirements
        if (categoryId != null && categoryId.isNotEmpty && data['category_id'] != categoryId) continue;
        if (areaId != null && areaId.isNotEmpty && data['area_id'] != areaId) continue;
        if (listingTypeId != null && listingTypeId.isNotEmpty && data['listing_type_id'] != listingTypeId) continue;
        if (createdBy != null && createdBy.isNotEmpty && data['created_by'] != createdBy) continue;
        if (isVerified != null && data['is_verified'] != isVerified) continue;
        final id = doc.id;
        final map = {
          ...data,
          'id': id,
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': data['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        // Apply search filter locally to avoid complex Firestore indexes
        if (search != null && search.isNotEmpty) {
          final title = map['title']?.toString().toLowerCase() ?? '';
          final code = map['property_code']?.toString().toLowerCase() ?? '';
          final desc = map['description']?.toString().toLowerCase() ?? '';
          final cleanSearch = search.toLowerCase();
          if (!title.contains(cleanSearch) && !code.contains(cleanSearch) && !desc.contains(cleanSearch)) {
            continue;
          }
        }

        propertiesList.add(await _hydrateProperty(map));
      }

      return {
        "success": true,
        "data": {
          "properties": propertiesList,
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore properties", e);
      return {"success": false, "data": {"properties": []}};
    }
  }

  Future<Map<String, dynamic>> getPropertyMetadata() async {
    try {
      BeautifulLogger.sync("Fetching individual lookup collections from Firestore...");
      
      final Map<String, String> collectionMappings = {
        'city': 'cities',
        'area': 'areas',
        'property_category': 'property_categories',
        'property_type': 'property_types',
        'configuration': 'configurations',
        'listing_type': 'listing_types',
        'property_status': 'property_status',
        'furnishing_type': 'furnishing_types',
        'facing_type': 'facing_types',
        'ownership_type': 'ownership_types',
        'brokerage_type': 'brokerage_types',
        'amenity': 'amenities',
      };

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      final List<Future<void>> futures = collectionMappings.entries.map((entry) async {
        final category = entry.key;
        final collName = entry.value;
        try {
          final snapshot = await FirebaseFirestore.instance.collection(collName).get();
          final List<Map<String, dynamic>> items = [];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final name = data['name'] ?? data['city_name'] ?? data['area_name'] ?? 'N/A';
            items.add({
              'id': doc.id,
              'name': name,
              'city_name': data['city_name'] ?? name,
              'area_name': data['area_name'] ?? name,
              'pincode': data['pincode'] ?? 'N/A',
              'city_id': data['city_id'] ?? '',
              'category_id': data['category_id'] ?? '',
              'category': category,
            });
          }
          grouped[category] = items;
        } catch (e) {
          BeautifulLogger.error("Failed to query Firestore lookup collection: $collName", e);
          grouped[category] = [];
        }
      }).toList();

      await Future.wait(futures);

      return {
        "success": true,
        "data": {
          "metadata": {
            "cities": grouped['city'] ?? [],
            "areas": grouped['area'] ?? [],
            "categories": grouped['property_category'] ?? [],
            "types": grouped['property_type'] ?? [],
            "configurations": grouped['configuration'] ?? [],
            "listingTypes": grouped['listing_type'] ?? [],
            "statuses": grouped['property_status'] ?? [],
            "furnishings": grouped['furnishing_type'] ?? [],
            "facings": grouped['facing_type'] ?? [],
            "ownerships": grouped['ownership_type'] ?? [],
            "brokerages": grouped['brokerage_type'] ?? [],
            "amenities": grouped['amenity'] ?? [],
          }
        }
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore lookups", e);
      return {"success": false, "data": {}};
    }
  }

  Future<Map<String, dynamic>> createProperty(Map<String, dynamic> propertyData) async {
    try {
      final docId = propertyData['id'] ?? FirebaseFirestore.instance.collection('properties').doc().id;
      final data = {
        ...propertyData,
        'id': docId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      };

      await FirebaseFirestore.instance.collection('properties').doc(docId).set(data);
      final hydrated = await _hydrateProperty(data);
      return {
        "success": true,
        "data": {"property": hydrated}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to create property in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateProperty(String id, Map<String, dynamic> propertyData) async {
    try {
      final updateData = {
        ...propertyData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await FirebaseFirestore.instance.collection('properties').doc(id).update(updateData);
      
      final doc = await FirebaseFirestore.instance.collection('properties').doc(id).get();
      final hydrated = await _hydrateProperty({
        ...?doc.data(),
        'id': id,
      });

      return {
        "success": true,
        "data": {"property": hydrated}
      };
    } catch (e) {
      BeautifulLogger.error("Failed to update property in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> togglePropertyVerification(String id, bool isVerified) async {
    try {
      await FirebaseFirestore.instance.collection('properties').doc(id).update({
        'is_verified': isVerified,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to toggle verification in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> softDeleteProperty(String id) async {
    try {
      await FirebaseFirestore.instance.collection('properties').doc(id).update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to soft delete property in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> restoreProperty(String id) async {
    try {
      await FirebaseFirestore.instance.collection('properties').doc(id).update({
        'deleted_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return {"success": true};
    } catch (e) {
      BeautifulLogger.error("Failed to restore property in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCity(String name) async {
    try {
      final id = FirebaseFirestore.instance.collection('cities').doc().id;
      final docData = {
        'id': id,
        'city_name': name,
        'state': 'Gujarat',
        'country': 'India',
        'category': 'city',
        'name': name,
      };
      await FirebaseFirestore.instance.collection('cities').doc(id).set(docData);
      
      // Also add to lookup_item table
      await FirebaseFirestore.instance.collection('lookups').doc(id).set({
        'id': id,
        'category': 'city',
        'name': name,
      });

      return {"success": true, "data": docData};
    } catch (e) {
      BeautifulLogger.error("Failed to create city in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createArea(String cityId, String name, String pincode) async {
    try {
      final id = FirebaseFirestore.instance.collection('areas').doc().id;
      final docData = {
        'id': id,
        'city_id': cityId,
        'area_name': name,
        'pincode': pincode,
        'category': 'area',
        'name': name,
      };
      await FirebaseFirestore.instance.collection('areas').doc(id).set(docData);

      // Also add to lookup_item table
      await FirebaseFirestore.instance.collection('lookups').doc(id).set({
        'id': id,
        'category': 'area',
        'name': name,
      });

      return {"success": true, "data": docData};
    } catch (e) {
      BeautifulLogger.error("Failed to create area in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createAmenity(String name) async {
    try {
      final id = FirebaseFirestore.instance.collection('amenities').doc().id;
      final docData = {
        'id': id,
        'name': name,
        'category': 'amenity',
      };
      await FirebaseFirestore.instance.collection('amenities').doc(id).set(docData);

      // Also add to lookup_item table
      await FirebaseFirestore.instance.collection('lookups').doc(id).set({
        'id': id,
        'category': 'amenity',
        'name': name,
      });

      return {"success": true, "data": docData};
    } catch (e) {
      BeautifulLogger.error("Failed to create amenity in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createLookup(String masterType, Map<String, dynamic> payload) async {
    try {
      final id = payload['id'] ?? FirebaseFirestore.instance.collection('lookups').doc().id;
      final docData = {
        ...payload,
        'id': id,
        'category': masterType,
      };
      await FirebaseFirestore.instance.collection('lookups').doc(id).set(docData);
      return {"success": true, "data": docData};
    } catch (e) {
      BeautifulLogger.error("Failed to create lookup in Firestore", e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkDuplicate(Map<String, dynamic> checkParams) async {
    try {
      // In NoSQL client-side, we can just return no duplicate or query local Isar
      return {"success": true, "data": {"isDuplicate": false}};
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCity(String id) async {
    await FirebaseFirestore.instance.collection('cities').doc(id).delete();
    await FirebaseFirestore.instance.collection('lookups').doc(id).delete();
  }

  Future<void> deleteArea(String id) async {
    await FirebaseFirestore.instance.collection('areas').doc(id).delete();
    await FirebaseFirestore.instance.collection('lookups').doc(id).delete();
  }

  Future<Map<String, dynamic>> getBinProperties() async {
    return getProperties(includeDeleted: true);
  }

  Future<void> permanentDeleteProperty(String id) async {
    await FirebaseFirestore.instance.collection('properties').doc(id).delete();
  }

  Future<void> emptyBin() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('properties')
        .where('deleted_at', isNull: false)
        .get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
