/// Skill 数据模型

class SkillModel {
  /// 唯一标识
  final String id;

  /// 显示名称
  final String name;

  /// Skill 内容（Markdown 格式）
  final String content;

  /// 文件路径
  final String filePath;

  /// 是否启用
  final bool isEnabled;

  /// 是否为系统内置
  final bool isBuiltin;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  const SkillModel({
    required this.id,
    required this.name,
    required this.content,
    this.filePath = '',
    this.isEnabled = false,
    this.isBuiltin = false,
    required this.createdAt,
    required this.updatedAt,
  });

  SkillModel copyWith({
    String? id,
    String? name,
    String? content,
    String? filePath,
    bool? isEnabled,
    bool? isBuiltin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SkillModel(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      isEnabled: isEnabled ?? this.isEnabled,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'filePath': filePath,
      'isEnabled': isEnabled,
      'isBuiltin': isBuiltin,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? false,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
