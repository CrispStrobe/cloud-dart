// models/file_item.dart
class FileItem {
  final String name;
  final String? path;
  final String? uuid;
  final bool isFolder;
  final int? size;
  final DateTime? updatedAt;

  FileItem({
    required this.name,
    this.path,
    this.uuid,
    required this.isFolder,
    this.size,
    this.updatedAt,
  });

  String get sizeFormatted {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileItem &&
          runtimeType == other.runtimeType &&
          (uuid != null ? uuid == other.uuid : path == other.path);

  @override
  int get hashCode => uuid?.hashCode ?? path.hashCode;
}
