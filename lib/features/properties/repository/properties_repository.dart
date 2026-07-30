import 'dart:convert';
import 'package:propkart/features/properties/models/property_model.dart';
import 'package:propkart/features/properties/services/properties_service.dart';

class PropertiesRepository {
  final PropertiesService _propertiesService = PropertiesService();

  void invalidateCache() {}

  Future<PropertyModel?> getPropertyById(String id) async {
    final response = await _propertiesService.getPropertyById(id);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final prop = data['property'];
    if (prop != null) {
      return PropertyModel.fromJson(prop);
    }
    return null;
  }

  Future<List<PropertyModel>> getProperties({
    String? search,
    String? categoryId,
    String? areaId,
    String? listingTypeId,
    String? createdBy,
    bool? isVerified,
    bool? includeDeleted,
  }) async {
    final response = await _propertiesService.getProperties(
      search: search,
      categoryId: categoryId,
      areaId: areaId,
      listingTypeId: listingTypeId,
      createdBy: createdBy,
      isVerified: isVerified,
      includeDeleted: includeDeleted,
    );
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final list = data['properties'] as List? ?? response['properties'] as List? ?? [];
    return list.map((item) => PropertyModel.fromJson(item)).toList();
  }

  Future<PropertyMetadataModel> getPropertyMetadata() async {
    final response = await _propertiesService.getPropertyMetadata();
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return PropertyMetadataModel.fromJson(data['metadata'] ?? {});
  }

  Future<void> fetchAndSaveMetadata() async {
    await getPropertyMetadata();
  }

  Future<LookupItem> createCity(String name) async {
    final response = await _propertiesService.createCity(name);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return LookupItem(id: data['id'] ?? '', name: data['city_name'] ?? '');
  }

  Future<AreaLookup> createArea(String cityId, String name, String pincode) async {
    final response = await _propertiesService.createArea(cityId, name, pincode);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return AreaLookup(
      id: data['id'] ?? '',
      name: data['area_name'] ?? '',
      cityId: data['city_id'] ?? '',
      pincode: data['pincode'] ?? '',
    );
  }

  Future<LookupItem> createAmenity(String name) async {
    final response = await _propertiesService.createAmenity(name);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return LookupItem(id: data['id'] ?? '', name: data['name'] ?? '');
  }

  Future<PropertyModel> createProperty(Map<String, dynamic> propertyData) async {
    final response = await _propertiesService.createProperty(propertyData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return PropertyModel.fromJson(data['property'] ?? {});
  }

  Future<PropertyModel> updateProperty(String id, Map<String, dynamic> propertyData) async {
    final response = await _propertiesService.updateProperty(id, propertyData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return PropertyModel.fromJson(data['property'] ?? {});
  }

  Future<PropertyModel> togglePropertyVerification(String id, bool isVerified) async {
    await _propertiesService.togglePropertyVerification(id, isVerified);
    return PropertyModel.fromJson({'id': id, 'is_verified': isVerified});
  }

  Future<PropertyModel> softDeleteProperty(String id) async {
    await _propertiesService.softDeleteProperty(id);
    return PropertyModel.fromJson({'id': id, 'title': 'Deleted'});
  }

  Future<PropertyModel> restoreProperty(String id) async {
    await _propertiesService.restoreProperty(id);
    return PropertyModel.fromJson({'id': id});
  }

  Future<LookupItem> createLookup(String masterType, Map<String, dynamic> payload) async {
    final response = await _propertiesService.createLookup(masterType, payload);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final key = masterType == 'property-type' ? 'propertyType' :
                masterType == 'listing-type' ? 'listingType' : masterType;
    final item = data[key] as Map<String, dynamic>? ?? data;
    if (masterType == 'area') {
      return AreaLookup.fromJson(item);
    } else {
      return LookupItem.fromJson(item);
    }
  }

  Future<Map<String, dynamic>> checkDuplicate(Map<String, dynamic> checkParams) async {
    final response = await _propertiesService.checkDuplicate(checkParams);
    return response['data'] as Map<String, dynamic>? ?? {};
  }
}
