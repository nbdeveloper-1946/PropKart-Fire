import 'dart:convert';
import 'package:propkart/features/requirements/models/requirement_model.dart';
import 'package:propkart/features/requirements/services/requirements_service.dart';
import 'package:propkart/core/security/role_guard.dart';

class RequirementsRepository {
  final RequirementsService _requirementsService = RequirementsService();

  void invalidateCache() {}

  Future<RequirementModel?> getRequirementById(String id) async {
    final response = await _requirementsService.getRequirementById(id);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final req = data['requirement'];
    if (req != null) {
      return RequirementModel.fromJson(req);
    }
    return null;
  }

  Future<List<RequirementModel>> getRequirements({
    String? search,
    String? configurationId,
    String? propertyTypeId,
    String? status,
    String? listingTypeId,
  }) async {
    final response = await _requirementsService.getRequirements(
      search: search,
      configurationId: configurationId,
      propertyTypeId: propertyTypeId,
      status: status,
      listingTypeId: listingTypeId,
    );
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final list = data['requirements'] as List? ?? response['requirements'] as List? ?? [];
    var requirements = list.map((item) => RequirementModel.fromJson(item)).toList();

    // Apply RBAC role-based filtering on Requirements
    final currentUser = RoleGuard.currentUser;
    if (currentUser != null) {
      final role = currentUser.role;
      if (role == 'Admin') {
        requirements = requirements.where((r) =>
          r.createdBy == currentUser.id || r.adminId == currentUser.id
        ).toList();
      } else if (role != 'Super Admin') {
        requirements = requirements.where((r) =>
          r.createdBy == currentUser.id
        ).toList();
      }
    }
    return requirements;
  }

  Future<RequirementModel> createRequirement(RequirementModel req) async {
    final response = await _requirementsService.createRequirement(req.toBackendJson());
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return RequirementModel.fromJson(data['requirement'] ?? {});
  }

  Future<RequirementModel> updateRequirement(RequirementModel req) async {
    final response = await _requirementsService.updateRequirement(req.id, req.toBackendJson());
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return RequirementModel.fromJson(data['requirement'] ?? {});
  }

  Future<void> deleteRequirement(String id) async {
    await _requirementsService.deleteRequirement(id);
  }
}
