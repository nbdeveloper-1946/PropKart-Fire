import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/logger.dart';

class DashboardService {
  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      BeautifulLogger.sync("Aggregating dashboard data directly from Firestore collections...");
      
      // 1. Fetch collections
      final propsSnapshot = await FirebaseFirestore.instance.collection("properties").where("deleted_at", isNull: true).get();
      final reqsSnapshot = await FirebaseFirestore.instance.collection("requirements").where("deleted_at", isNull: true).get();
      final usersSnapshot = await FirebaseFirestore.instance.collection("users").where("deleted_at", isNull: true).get();
      final followupsSnapshot = await FirebaseFirestore.instance.collection("followups").where("deleted_at", isNull: true).get();
      final visitsSnapshot = await FirebaseFirestore.instance.collection("site_visits").where("deleted_at", isNull: true).get();
      final checklistSnapshot = await FirebaseFirestore.instance.collection("checklists").get();

      // Fetch status and listing types to resolve available/rent IDs dynamically
      final statusSnapshot = await FirebaseFirestore.instance.collection("property_status").get();
      final typesSnapshot = await FirebaseFirestore.instance.collection("listing_types").get();

      // Resolve "Available" status IDs
      final availableStatusIds = statusSnapshot.docs
          .where((doc) => (doc.data()['name'] as String? ?? '').toLowerCase().contains('avail'))
          .map((doc) => doc.id)
          .toSet();

      // Resolve "Rent" listing type IDs
      final rentListingTypeIds = typesSnapshot.docs
          .where((doc) => (doc.data()['name'] as String? ?? '').toLowerCase().contains('rent'))
          .map((doc) => doc.id)
          .toSet();

      // Convert docs
      final properties = propsSnapshot.docs.map((doc) => doc.data()).toList();
      final requirements = reqsSnapshot.docs.map((doc) => doc.data()).toList();
      final usersCount = usersSnapshot.docs.where((doc) => doc.data()['is_active'] == true).length;

      // 2. Count statuses and listing types
      int totalProperties = properties.length;
      int available = 0;
      int rentalAvailable = 0;
      int resaleAvailable = 0;

      for (final p in properties) {
        final statusId = p['property_status_id']?.toString() ?? '';
        final listingId = p['listing_type_id']?.toString() ?? '';

        final isAvailable = availableStatusIds.contains(statusId);
        if (isAvailable) {
          available++;
          final isRent = rentListingTypeIds.contains(listingId);
          if (isRent) {
            rentalAvailable++;
          } else {
            resaleAvailable++;
          }
        }
      }

      int activeRequirements = requirements.where((r) =>
        !["Won", "Dead", "Not Interested", "Bin"].contains(r['status'])
      ).length;

      // 3. Populate lists
      final List<Map<String, dynamic>> followupsList = [];
      for (final doc in followupsSnapshot.docs) {
        final data = doc.data();
        followupsList.add({
          'id': doc.id,
          'requirement_id': data['requirement_id'] ?? '',
          'requirement_customer_name': data['requirement_customer_name'] ?? data['client_name'] ?? 'Client',
          'client_name': data['client_name'] ?? '',
          'mobile': data['mobile'] ?? '',
          'followup_date': data['followup_date'] ?? DateTime.now().toIso8601String(),
          'notes': data['notes'] ?? data['remarks'] ?? '',
          'status': data['status'] ?? 'Pending',
        });
      }

      final List<Map<String, dynamic>> siteVisitsList = [];
      for (final doc in visitsSnapshot.docs) {
        final data = doc.data();
        siteVisitsList.add({
          'id': doc.id,
          'requirement_id': data['requirement_id'] ?? '',
          'requirement_customer_name': data['requirement_customer_name'] ?? 'Client',
          'visit_date': data['visit_date'] ?? DateTime.now().toIso8601String(),
          'remarks': data['remarks'] ?? '',
          'status': data['status'] ?? 'Scheduled',
        });
      }

      final List<Map<String, dynamic>> checklistList = [];
      for (final doc in checklistSnapshot.docs) {
        final data = doc.data();
        checklistList.add({
          'id': doc.id,
          'task': data['task'] ?? '',
          'is_completed': data['is_completed'] ?? false,
        });
      }

      final summary = {
        "totalProperties": totalProperties,
        "available": available,
        "sold": 0,
        "rented": 0,
        "requirements": activeRequirements,
        "users": usersCount,
        "rentalAvailable": rentalAvailable,
        "resaleAvailable": resaleAvailable,
        "rentalRented": 0,
        "resaleSold": 0,
        "rentalRequirements": requirements.where((r) => rentListingTypeIds.contains(r['listing_type_id']?.toString())).length,
        "resaleRequirements": requirements.where((r) => !rentListingTypeIds.contains(r['listing_type_id']?.toString())).length,
        "rentalWonRequirements": 0,
        "resaleWonRequirements": 0,
        "totalPropertiesTrend": 0,
        "availableTrend": 0,
        "soldTrend": 0,
        "rentedTrend": 0,
        "requirementsTrend": 0,
        "topBroker": "N/A",
        "topArea": "N/A",
        "topProperty": "N/A",
        "monthlyGrowth": 0.0
      };

      return {
        "success": true,
        "summary": summary,
        "followups": followupsList,
        "siteVisits": siteVisitsList,
        "checklist": checklistList,
        "activity": [],
        "recentProperties": []
      };
    } catch (e) {
      BeautifulLogger.error("Failed to query Firestore dashboard metrics", e);
      return {
        "success": false,
        "summary": {},
        "followups": [],
        "siteVisits": [],
        "checklist": [],
        "activity": [],
        "recentProperties": []
      };
    }
  }
}
