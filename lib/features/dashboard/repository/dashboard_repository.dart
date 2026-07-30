import 'package:propkart/features/dashboard/models/dashboard_summary.dart';
import 'package:propkart/features/dashboard/services/dashboard_service.dart';
import 'package:propkart/features/requirements/services/requirements_service.dart';
import 'package:propkart/features/requirements/models/requirement_model.dart';
import 'package:propkart/core/security/role_guard.dart';

class DashboardRepository {
  final DashboardService _dashboardService = DashboardService();
  final RequirementsService _requirementsService = RequirementsService();

  Future<DashboardData> getDashboardData({bool forceRefresh = false}) async {
    final response = await _dashboardService.getDashboardData();
    final model = DashboardData.fromJson(response);

    // Fetch requirements to apply RBAC filtering and dynamic counts
    final reqsResponse = await _requirementsService.getRequirements();
    final list = reqsResponse['data']?['requirements'] as List? ?? [];
    var requirements = list.map((item) => RequirementModel.fromJson(item)).toList();

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

    int rentalReqs = 0;
    int resaleReqs = 0;
    int rentalWonReqs = 0;
    int resaleWonReqs = 0;
    int rentalSiteVisits = 0;
    int resaleSiteVisits = 0;

    for (final item in requirements) {
      if (item.status == 'Bin') continue;

      final name = item.listingTypeName ?? '';
      final id = item.listingTypeId ?? '';
      final combined = '$name $id'.toLowerCase();
      final isWon = item.status == 'Won' || item.status == 'Closed';
      final isSiteVisit = item.status == 'Site Visit Done' ||
          item.status == 'Negotiation' ||
          item.status == 'Won' ||
          item.status == 'Closed';

      if (combined.contains('rent')) {
        if (isWon) {
          rentalWonReqs++;
        } else {
          rentalReqs++;
        }
        if (isSiteVisit) {
          rentalSiteVisits++;
        }
      } else if (combined.contains('sale') || combined.contains('resale')) {
        if (isWon) {
          resaleWonReqs++;
        } else {
          resaleReqs++;
        }
        if (isSiteVisit) {
          resaleSiteVisits++;
        }
      }
    }

    final allowedReqIds = requirements.map((r) => r.id).toSet();
    final allowedClientNames = requirements.map((r) => r.clientName.toLowerCase()).toSet();

    bool isAllowedItem(String? reqId, String? clientName) {
      if (reqId != null && reqId.isNotEmpty) return allowedReqIds.contains(reqId);
      if (clientName != null && clientName.isNotEmpty) return allowedClientNames.contains(clientName.toLowerCase());
      return false;
    }

    final updatedSummary = DashboardSummary(
      totalProperties: model.summary.totalProperties,
      available: model.summary.available,
      sold: model.summary.sold,
      rented: model.summary.rented,
      requirements: rentalReqs + resaleReqs,
      users: model.summary.users,
      rentalAvailable: model.summary.rentalAvailable,
      resaleAvailable: model.summary.resaleAvailable,
      rentalRented: model.summary.rentalRented,
      resaleSold: model.summary.resaleSold,
      rentalRequirements: rentalReqs,
      resaleRequirements: resaleReqs,
      rentalWonRequirements: rentalWonReqs,
      resaleWonRequirements: resaleWonReqs,
      totalPropertiesTrend: model.summary.totalPropertiesTrend,
      availableTrend: model.summary.availableTrend,
      soldTrend: model.summary.soldTrend,
      rentedTrend: model.summary.rentedTrend,
      requirementsTrend: model.summary.requirementsTrend,
      topBroker: model.summary.topBroker,
      topArea: model.summary.topArea,
      topProperty: model.summary.topProperty,
      monthlyGrowth: model.summary.monthlyGrowth,
    );

    final filteredFollowups = model.followups.where((f) =>
      isAllowedItem(f.requirementId, f.requirementCustomerName)
    ).toList();

    final filteredSiteVisits = model.siteVisits.where((sv) =>
      isAllowedItem(sv.requirementId, sv.requirementCustomerName)
    ).toList();

    return DashboardData(
      summary: updatedSummary,
      activity: model.activity,
      recentProperties: model.recentProperties,
      checklist: model.checklist,
      followups: filteredFollowups,
      siteVisits: filteredSiteVisits,
    );
  }
}
