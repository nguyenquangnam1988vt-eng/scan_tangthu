class Session {
  String caseName;
  List<PersonEntry> persons;

  Session({this.caseName = '', List<PersonEntry>? persons})
      : persons = persons ?? [];

  int get totalFiles => persons.fold(0, (s, p) => s + p.totalFiles);
  int get totalProcedures =>
      persons.fold(0, (s, p) => s + p.procedures.length);

  Map<String, dynamic> toJson() => {
        'caseName': caseName,
        'persons': persons.map((e) => e.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        caseName: j['caseName'] ?? '',
        persons: (j['persons'] as List? ?? [])
            .map((e) => PersonEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PersonEntry {
  String name;
  List<ProcedureEntry> procedures;

  PersonEntry({required this.name, List<ProcedureEntry>? procedures})
      : procedures = procedures ?? [];

  int get totalFiles => procedures.fold(0, (s, p) => s + p.pdfs.length);

  Map<String, dynamic> toJson() => {
        'name': name,
        'procedures': procedures.map((e) => e.toJson()).toList(),
      };

  factory PersonEntry.fromJson(Map<String, dynamic> j) => PersonEntry(
        name: j['name'] ?? '',
        procedures: (j['procedures'] as List? ?? [])
            .map((e) =>
                ProcedureEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class ProcedureEntry {
  String name;
  List<String> pdfs;

  ProcedureEntry({required this.name, List<String>? pdfs})
      : pdfs = pdfs ?? [];

  Map<String, dynamic> toJson() => {'name': name, 'pdfs': pdfs};

  factory ProcedureEntry.fromJson(Map<String, dynamic> j) => ProcedureEntry(
        name: j['name'] ?? '',
        pdfs: (j['pdfs'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

/// Chế độ quét
enum ScanMode { color, grayscale, bw }