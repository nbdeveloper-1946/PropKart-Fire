import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:propkart/core/utils/logger.dart';
import 'isar_collections.dart';
import 'local_repositories.dart';

class IsarService {
  static final IsarService _instance = IsarService._internal();
  factory IsarService() => _instance;
  IsarService._internal();

  Isar? _isar;

  Isar get isar {
    if (_isar == null) {
      if (kIsWeb) {
        throw StateError("Isar database is not available on Flutter Web. Running in-memory instead.");
      }
      throw StateError("Isar has not been initialized. Call initialize() first.");
    }
    return _isar!;
  }

  Future<void> initialize() async {
    if (_isar != null) return;

    if (kIsWeb) {
      BeautifulLogger.info("Bypassing Isar.open. Running local repositories in-memory.");
      await LookupLocalRepository().loadInMemoryCache();
      await PropertyLocalRepository().loadInMemoryCache();
      await RequirementLocalRepository().loadInMemoryCache();
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        LookupItemLocalSchema,
        PropertyLocalSchema,
        RequirementLocalSchema,
        FollowupLocalSchema,
        BuilderLocalSchema,
        OwnerLocalSchema,
        ClientLocalSchema,
        OutboxLocalSchema,
        DashboardLocalSchema,
      ],
      directory: dir.path,
    );
    await _migrateRequirements();
  }

  Future<void> _migrateRequirements() async {
    final requirements = await _isar!.requirementLocals.where().findAll();
    final toUpdate = <RequirementLocal>[];

    for (final req in requirements) {
      if (req.listingTypeId == null) {
        String? remarksStr = req.remarks;
        String? listingTypeId;
        String? listingTypeName;
        String? cleanRemarks = remarksStr;

        if (remarksStr != null && remarksStr.startsWith('[lt:')) {
          final closeBracketIdx = remarksStr.indexOf(']');
          if (closeBracketIdx != -1) {
            final content = remarksStr.substring('[lt:'.length, closeBracketIdx);
            final parts = content.split(':');
            if (parts.isNotEmpty) {
              listingTypeId = parts[0];
              if (parts.length > 1) {
                listingTypeName = parts[1];
              }
            }
            cleanRemarks = remarksStr.substring(closeBracketIdx + 1).trim();
            if (cleanRemarks.isEmpty) cleanRemarks = null;
          }
        }

        req.listingTypeId = listingTypeId ?? 'Unknown';
        req.listingTypeName = listingTypeName ?? 'Unknown';
        req.remarks = cleanRemarks;
        toUpdate.add(req);
      }
    }

    if (toUpdate.isNotEmpty) {
      BeautifulLogger.sync("Migrating ${toUpdate.length} requirements with listing type columns...");
      await _isar!.writeTxn(() async {
        await _isar!.requirementLocals.putAll(toUpdate);
      });
      BeautifulLogger.success("Requirements migration complete.");
    }
  }

  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.clear();
    });
  }
}
