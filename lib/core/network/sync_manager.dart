import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:propkart/core/api/api_constants.dart';
import 'package:propkart/core/api/api_client.dart';
import 'package:propkart/core/storage/isar_service.dart';
import 'package:propkart/core/storage/repository_coordinator.dart';
import 'package:propkart/core/storage/local_repositories.dart';
import 'package:propkart/core/storage/performance_logger.dart';
import 'package:propkart/core/storage/isar_collections.dart';
import 'package:propkart/features/properties/models/property_model.dart';
import 'package:propkart/features/properties/services/properties_service.dart';
import 'package:propkart/features/requirements/models/requirement_model.dart';
import 'package:propkart/features/requirements/services/requirements_service.dart';
import 'package:propkart/features/dashboard/models/dashboard_summary.dart';
import 'package:propkart/features/builders/models/builder_model.dart';
import 'package:propkart/features/builders/services/builders_service.dart';
import 'package:propkart/features/owners/models/owner_model.dart';
import 'package:propkart/features/owners/services/owners_service.dart';
import 'package:propkart/core/storage/model_mappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:propkart/features/properties/repository/properties_repository.dart';
import 'package:propkart/core/utils/logger.dart';

enum SyncState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  syncing,
  offline
}

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final RepositoryCoordinator _coordinator = RepositoryCoordinator();

  final List<StreamSubscription> _firestoreSubscriptions = [];

  SyncState _state = SyncState.disconnected;
  SyncState get state => _state;

  bool isSyncCompleted = false;
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  Future<void> performStartupSync() async {
    isSyncing.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientVersion = prefs.getInt('last_lookup_version') ?? 0;
      
      int serverVersion = 1;
      try {
        final doc = await FirebaseFirestore.instance.collection('config').doc('sync_status').get();
        if (doc.exists) {
          serverVersion = doc.data()?['schemaVersion'] ?? 1;
        }
      } catch (e) {
        BeautifulLogger.warning("Failed to fetch Firestore config status, defaulting to 1: $e");
      }
      
      final lookupCount = await _coordinator.lookupLocal.getLookupsCount();
      if (lookupCount == 0 || serverVersion != clientVersion) {
        BeautifulLogger.sync("Lookup version mismatch or empty. Downloading lookup tables...");
        await PropertiesRepository().fetchAndSaveMetadata();
        if (serverVersion > 0) {
          await prefs.setInt('last_lookup_version', serverVersion);
        }
      } else {
        BeautifulLogger.success("Lookup tables up to date (version: $clientVersion). Skipping lookup sync.");
      }
      
      await triggerDeltaSync();
      isSyncCompleted = true;
    } finally {
      isSyncing.value = false;
    }
  }

  final _stateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  int _ref = 0;
  int _reconnectAttempts = 0;

  final List<Map<String, dynamic>> _incomingBuffer = [];
  Timer? _batchTimer;

  Future<void> initialize() async {
    // Realtime must only connect after authentication — call [connectAfterAuth].
    ApiConstants.assertConfig();
  }

  /// Connect realtime only when a user session exists.
  Future<void> connectAfterAuth() async {
    if (!ApiConstants.hasSupabaseConfig) return;
    await connect();
  }

  void _updateState(SyncState newState) {
    _state = newState;
    _stateController.add(newState);
    BeautifulLogger.sync("State Changed to: $newState");
  }

  Future<void> connect() async {
    if (_state == SyncState.connected || _state == SyncState.connecting) return;
    _updateState(SyncState.connecting);

    try {
      // 1. Initial delta sync
      await triggerDeltaSync();
      
      // 2. Set up Firestore Snapshot Listeners
      await _initFirestoreListeners();

      _updateState(SyncState.connected);
      _reconnectAttempts = 0;
      PerformanceLogger().logMetric(
        operation: 'SyncManager: Firestore connected successfully',
        totalMs: 0,
      );
    } catch (e) {
      _updateState(SyncState.disconnected);
      BeautifulLogger.error("Failed to connect Firestore listeners", e);
    }
  }

  Future<void> _initFirestoreListeners() async {
    // Clear old subscriptions first
    for (final s in _firestoreSubscriptions) {
      await s.cancel();
    }
    _firestoreSubscriptions.clear();

    // 1. Listen to properties
    _firestoreSubscriptions.add(
      FirebaseFirestore.instance.collection("properties").where("deleted_at", isNull: true).snapshots().listen((snapshot) async {
        final List<PropertyLocal> pList = snapshot.docs.map((doc) => PropertyModel.fromJson({...doc.data(), 'id': doc.id}).toLocal()).toList();
        if (kIsWeb) {
          PropertyLocalRepository.inMemory.clear();
          for (final p in pList) PropertyLocalRepository.inMemory[p.id] = p;
        } else {
          final isar = IsarService().isar;
          await isar.writeTxn(() async {
            await isar.propertyLocals.clear();
            await isar.propertyLocals.putAll(pList);
          });
        }
        _coordinator.refreshProperties();
      })
    );

    // 2. Listen to requirements
    _firestoreSubscriptions.add(
      FirebaseFirestore.instance.collection("requirements").where("deleted_at", isNull: true).snapshots().listen((snapshot) async {
        final List<RequirementLocal> rList = snapshot.docs.map((doc) => RequirementModel.fromJson({...doc.data(), 'id': doc.id}).toLocal()).toList();
        if (kIsWeb) {
          RequirementLocalRepository.inMemory.clear();
          for (final r in rList) RequirementLocalRepository.inMemory[r.id] = r;
        } else {
          final isar = IsarService().isar;
          await isar.writeTxn(() async {
            await isar.requirementLocals.clear();
            await isar.requirementLocals.putAll(rList);
          });
        }
        _coordinator.refreshRequirements();
      })
    );

    // 3. Listen to builders
    _firestoreSubscriptions.add(
      FirebaseFirestore.instance.collection("builders").snapshots().listen((snapshot) async {
        final List<BuilderLocal> bList = snapshot.docs.map((doc) => BuilderModel.fromJson({...doc.data(), 'id': doc.id}).toLocal()).toList();
        if (kIsWeb) {
          BuilderLocalRepository.inMemory.clear();
          for (final b in bList) BuilderLocalRepository.inMemory[b.id] = b;
        } else {
          final isar = IsarService().isar;
          await isar.writeTxn(() async {
            await isar.builderLocals.clear();
            await isar.builderLocals.putAll(bList);
          });
        }
        _coordinator.refreshBuilders();
      })
    );

    // 4. Listen to owners
    _firestoreSubscriptions.add(
      FirebaseFirestore.instance.collection("owners").snapshots().listen((snapshot) async {
        final List<OwnerLocal> oList = snapshot.docs.map((doc) => OwnerModel.fromJson({...doc.data(), 'id': doc.id}).toLocal()).toList();
        if (kIsWeb) {
          OwnerLocalRepository.inMemory.clear();
          for (final o in oList) OwnerLocalRepository.inMemory[o.id] = o;
        } else {
          final isar = IsarService().isar;
          await isar.writeTxn(() async {
            await isar.ownerLocals.clear();
            await isar.ownerLocals.putAll(oList);
          });
        }
        _coordinator.refreshOwners();
      })
    );

    // 5. Listen to followups
    _firestoreSubscriptions.add(
      FirebaseFirestore.instance.collection("followups").where("deleted_at", isNull: true).snapshots().listen((snapshot) async {
        final List<FollowupLocal> fList = snapshot.docs.map((doc) => DashboardFollowup.fromJson({...doc.data(), 'id': doc.id}).toLocal('System')).toList();
        if (kIsWeb) {
          FollowupLocalRepository.inMemory.clear();
          for (final f in fList) FollowupLocalRepository.inMemory[f.id] = f;
        } else {
          final isar = IsarService().isar;
          await isar.writeTxn(() async {
            await isar.followupLocals.clear();
            await isar.followupLocals.putAll(fList);
          });
        }
        _coordinator.refreshDashboard();
      })
    );
  }

  Future<void> disconnect() async {
    for (final s in _firestoreSubscriptions) {
      await s.cancel();
    }
    _firestoreSubscriptions.clear();
    isSyncCompleted = false;
    isSyncing.value = false;
    _updateState(SyncState.disconnected);
  }

  Future<void> triggerDeltaSync() async {
    _updateState(SyncState.syncing);
    BeautifulLogger.sync("Starting Delta Sync...");
    final start = DateTime.now();

    try {
      // 1. Fetch fresh lists from backend services
      final propRes = await PropertiesService().getProperties();
      final reqRes = await RequirementsService().getRequirements();
      final builderRes = await BuildersService().getBuilders();
      final ownerRes = await OwnersService().getOwners();

      final List<dynamic> serverProperties = propRes['properties'] ?? propRes['data']?['properties'] ?? [];
      final List<dynamic> serverRequirements = reqRes['requirements'] ?? reqRes['data']?['requirements'] ?? [];
      final List<dynamic> serverBuilders = builderRes['builders'] ?? builderRes['data']?['builders'] ?? [];
      final List<dynamic> serverOwners = ownerRes['owners'] ?? ownerRes['data']?['owners'] ?? [];

      // 2. Perform Conflict Detection before replaying outbox
      final outboxItems = await _coordinator.outboxLocal.getQueuedRequests();
      final conflictedIds = <String>{};

      for (final item in outboxItems) {
        final uriParts = item.endpoint.split('/');
        final targetId = uriParts.length > 2 ? uriParts[2] : null;

        if (targetId != null) {
          if (item.endpoint.startsWith('/properties')) {
            final serverItem = serverProperties.firstWhere((p) => p['id'] == targetId, orElse: () => null);
            if (serverItem != null && serverItem['updated_at'] != null) {
              final serverUpdatedAt = DateTime.parse(serverItem['updated_at']);
              if (serverUpdatedAt.isAfter(item.createdAt)) {
                conflictedIds.add(item.id);
                BeautifulLogger.warning("Property $targetId has a newer server edit (Conflict). Server wins.");
              }
            }
          } else if (item.endpoint.startsWith('/requirements')) {
            final serverItem = serverRequirements.firstWhere((r) => r['id'] == targetId, orElse: () => null);
            if (serverItem != null && serverItem['updated_at'] != null) {
              final serverUpdatedAt = DateTime.parse(serverItem['updated_at']);
              if (serverUpdatedAt.isAfter(item.createdAt)) {
                conflictedIds.add(item.id);
                BeautifulLogger.warning("Requirement $targetId has a newer server edit (Conflict). Server wins.");
              }
            }
          }
        }
      }

      // Remove conflicted outbox requests (Server-wins conflict policy)
      for (final outboxId in conflictedIds) {
        await _coordinator.outboxLocal.removeRequest(outboxId);
      }

      // 3. Replay remaining safe outbox operations
      await processOutboxQueue();

      // 4. Merge server data into local database
      final pList = serverProperties.map((item) => PropertyModel.fromJson(item).toLocal()).toList();
      final rList = serverRequirements.map((item) => RequirementModel.fromJson(item).toLocal()).toList();
      final bList = serverBuilders.map((item) => BuilderModel.fromJson(item).toLocal()).toList();
      final oList = serverOwners.map((item) => OwnerModel.fromJson(item).toLocal()).toList();

      if (kIsWeb) {
        PropertyLocalRepository.inMemory.clear();
        for (final p in pList) PropertyLocalRepository.inMemory[p.id] = p;

        RequirementLocalRepository.inMemory.clear();
        for (final r in rList) RequirementLocalRepository.inMemory[r.id] = r;

        BuilderLocalRepository.inMemory.clear();
        for (final b in bList) BuilderLocalRepository.inMemory[b.id] = b;

        OwnerLocalRepository.inMemory.clear();
        for (final o in oList) OwnerLocalRepository.inMemory[o.id] = o;
      } else {
        final isar = IsarService().isar;
        await isar.writeTxn(() async {
          await isar.propertyLocals.clear();
          await isar.propertyLocals.putAll(pList);

          await isar.requirementLocals.clear();
          await isar.requirementLocals.putAll(rList);

          await isar.builderLocals.clear();
          await isar.builderLocals.putAll(bList);

          await isar.ownerLocals.clear();
          await isar.ownerLocals.putAll(oList);
        });
      }

      _coordinator.refreshProperties();
      _coordinator.refreshRequirements();
      _coordinator.refreshBuilders();
      _coordinator.refreshOwners();

    } catch (e) {
      BeautifulLogger.error("Delta Sync failed", e);
    }
  }

  Future<void> processOutboxQueue() async {
    BeautifulLogger.sync("Replaying Outbox Queue...");
    final start = DateTime.now();
    final outboxItems = await _coordinator.outboxLocal.getQueuedRequests();

    if (outboxItems.isEmpty) return;

    int replayedCount = 0;

    for (final item in outboxItems) {
      try {
        final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
        final uriParts = item.endpoint.split('/');
        if (uriParts.length < 2) continue;

        String collectionName = uriParts[1];
        String? docId = uriParts.length > 2 ? uriParts[2] : null;

        // Route subpaths
        if (item.endpoint == '/properties/cities') {
          collectionName = 'cities';
          docId = payload['id'];
        } else if (item.endpoint == '/properties/areas') {
          collectionName = 'areas';
          docId = payload['id'];
        } else if (item.endpoint == '/properties/amenities') {
          collectionName = 'amenities';
          docId = payload['id'];
        }

        BeautifulLogger.sync("Replaying outbox item: ${item.method} ${item.endpoint}");

        if (item.method == 'POST') {
          final targetId = payload['id'] ?? docId ?? FirebaseFirestore.instance.collection(collectionName).doc().id;
          final docData = {
            ...payload,
            'id': targetId,
            'created_at': payload['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'deleted_at': null,
          };
          await FirebaseFirestore.instance.collection(collectionName).doc(targetId).set(docData);

          // For cities, areas, and amenities, also write to lookups collection
          if (['cities', 'areas', 'amenities'].contains(collectionName)) {
            final String category = collectionName == 'cities' ? 'city' : (collectionName == 'areas' ? 'area' : 'amenity');
            final String name = payload['city_name'] ?? payload['area_name'] ?? payload['name'] ?? 'N/A';
            await FirebaseFirestore.instance.collection('lookups').doc(targetId).set({
              'id': targetId,
              'category': category,
              'name': name,
            });
          }
        } else if (item.method == 'PUT' && docId != null) {
          final docData = {
            ...payload,
            'updated_at': DateTime.now().toIso8601String(),
          };
          await FirebaseFirestore.instance.collection(collectionName).doc(docId).update(docData);
        } else if (item.method == 'DELETE' && docId != null) {
          if (item.endpoint.endsWith('/permanent')) {
            await FirebaseFirestore.instance.collection(collectionName).doc(docId).delete();
          } else {
            await FirebaseFirestore.instance.collection(collectionName).doc(docId).update({
              'deleted_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        }

        await _coordinator.outboxLocal.removeRequest(item.id);
        replayedCount++;
      } catch (e) {
        BeautifulLogger.error("Outbox replay failed for ${item.endpoint}", e);
        break; // Stop replaying on failure, retry on next cycle
      }
    }

    if (replayedCount > 0) {
      final totalMs = DateTime.now().difference(start).inMilliseconds;
      PerformanceLogger().logMetric(
        operation: 'Replayed $replayedCount outbox items',
        totalMs: totalMs,
      );
    }
  }

  Future<Map<String, dynamic>> _enrichRawRecord(String table, Map<String, dynamic> record) async {
    final enriched = Map<String, dynamic>.from(record);

    Future<String> getName(String category, String? id) async {
      if (id == null || id.isEmpty) return 'N/A';
      if (kIsWeb) {
        for (final l in LookupLocalRepository.inMemory.values) {
          if (l.category == category && l.id == id) {
            return l.name;
          }
        }
        return 'N/A';
      } else {
        final isar = IsarService().isar;
        final match = await isar.lookupItemLocals.filter().categoryEqualTo(category).idEqualTo(id).findFirst();
        return match?.name ?? 'N/A';
      }
    }

    if (table == "properties") {
      enriched['category'] = {'name': await getName('property_category', record['category_id'])};
      enriched['property_type'] = {'name': await getName('property_type', record['property_type_id'])};
      enriched['configuration'] = {'name': await getName('configuration', record['configuration_id'])};
      enriched['listing_type'] = {'name': await getName('listing_type', record['listing_type_id'])};
      enriched['property_status'] = {'name': await getName('property_status', record['property_status_id'])};
      enriched['city'] = {'city_name': await getName('city', record['city_id'])};
      enriched['area'] = {
        'area_name': await getName('area', record['area_id']),
        'pincode': record['pincode'] ?? 'N/A'
      };
      
      enriched['furnishing_type'] = {'name': await getName('furnishing_type', record['furnishing_type_id'])};
      enriched['facing_type'] = {'name': await getName('facing_type', record['facing_type_id'])};
      enriched['ownership_type'] = {'name': await getName('ownership_type', record['ownership_type_id'])};
      enriched['brokerage_type'] = {'name': await getName('brokerage_type', record['brokerage_type_id'])};
    } else if (table == "requirements") {
      enriched['category'] = {'name': await getName('property_category', record['category_id'])};
      enriched['property_type'] = {'name': await getName('property_type', record['property_type_id'])};
      enriched['configuration'] = {'name': await getName('configuration', record['configuration_id'])};
      enriched['listing_type'] = {'name': await getName('listing_type', record['listing_type_id'])};
      enriched['city'] = {'city_name': await getName('city', record['city_id'])};
      enriched['area'] = {'area_name': await getName('area', record['area_id'])};
    }

    return enriched;
  }
}
