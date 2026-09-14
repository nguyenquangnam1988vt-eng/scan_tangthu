import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/session.dart';

class SessionService {
  static const _metaName = '_session.json';

  static Future<Directory> getRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/current_session');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _metaFile() async {
    final root = await getRoot();
    return File('${root.path}/$_metaName');
  }

  static Future<Session> load() async {
    final f = await _metaFile();
    if (!await f.exists()) return Session();
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Session.fromJson(j);
    } catch (_) {
      return Session();
    }
  }

  static Future<void> save(Session s) async {
    final f = await _metaFile();
    await f.writeAsString(jsonEncode(s.toJson()));
  }

  static Future<Directory> ensureProcedureDir(
      String caseName, String person, String procedure) async {
    final root = await getRoot();
    final dir = Directory('${root.path}/$caseName/$person/$procedure');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> resolvePdf(String caseName, String person,
      String procedure, String fileName) async {
    final root = await getRoot();
    return File('${root.path}/$caseName/$person/$procedure/$fileName');
  }

  static Future<Directory> getCaseDir(String caseName) async {
    final root = await getRoot();
    return Directory('${root.path}/$caseName');
  }

  static Future<void> renameFolder(String oldRel, String newRel) async {
    final root = await getRoot();
    final oldDir = Directory('${root.path}/$oldRel');
    if (!await oldDir.exists()) return;
    final newDir = Directory('${root.path}/$newRel');
    if (await newDir.exists()) {
      throw Exception('Thư mục "$newRel" đã tồn tại');
    }
    await newDir.parent.create(recursive: true);
    await oldDir.rename(newDir.path);
  }

  static Future<void> clearAll() async {
    final root = await getRoot();
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }

  static Future<void> deleteFile(String caseName, String person,
      String procedure, String fileName) async {
    final f = await resolvePdf(caseName, person, procedure, fileName);
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteProcedureDir(
      String caseName, String person, String procedure) async {
    final root = await getRoot();
    final dir = Directory('${root.path}/$caseName/$person/$procedure');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> deletePersonDir(String caseName, String person) async {
    final root = await getRoot();
    final dir = Directory('${root.path}/$caseName/$person');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}