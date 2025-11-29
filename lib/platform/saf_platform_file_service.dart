import 'package:flutter/services.dart'; // NEW

import 'package:saf_util/saf_util.dart';

import '../data/file_handler/file_handler.dart';
import '../data/file_handler/local_file_handler_saf.dart'; // For CustomSAFDocumentFile
import 'platform_file_service.dart';

/// An Android-specific implementation of [PlatformFileService] that uses
/// the Storage Access Framework (SAF).
class SafPlatformFileService implements PlatformFileService {
  final SafUtil _safUtil = SafUtil();

  @override
  Future<bool> hasPermission(String uri) async {
    // This is the logic moved from the old SafFileHandler.
    final hasPersisted = await _safUtil.hasPersistedPermission(
      uri,
      checkRead: true,
      checkWrite: true,
    );
    if (hasPersisted == false) {
      return false;
    }

    // A persisted permission doesn't always guarantee access (e.g., SD card removed).
    // A 'stat' call is a reliable way to verify actual, current access.
    try {
      final stat = await _safUtil.stat(uri, true);
      return stat != null;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        return false;
      }
      // Other platform exceptions might occur, treat them as no access.
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ProjectDocumentFile?> pickDirectoryForProject() async {
    final dir = await _safUtil.pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    return dir != null ? CustomSAFDocumentFile(dir) : null;
  }

  @override
  Future<bool> reRequestProjectPermission(String uri) async {
    final dir = await _safUtil.pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    // The user must select the exact same directory for permission to be re-granted.
    return dir != null && dir.uri == uri;
  }

  @override
  Future<ProjectDocumentFile?> pickFileForImport() async {
    final file = await _safUtil.pickFile();
    return file != null ? CustomSAFDocumentFile(file) : null;
  }

  @override
  Future<List<ProjectDocumentFile>> pickFilesForImport() async {
    final files = await _safUtil.pickFiles();
    return files?.map((f) => CustomSAFDocumentFile(f)).toList() ?? [];
  }
}