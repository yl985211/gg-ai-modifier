/// 插件中心页面
/// 支持 Skill 导入、管理、启用/禁用

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/skill_model.dart';
import '../../main.dart';

/// Skill 列表 Provider
final skillsProvider = StateProvider<List<SkillModel>>((ref) => []);

/// 插件中心页面
class PluginCenterPage extends ConsumerStatefulWidget {
  const PluginCenterPage({super.key});

  @override
  ConsumerState<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends ConsumerState<PluginCenterPage> {
  /// 系统内置 Skill
  static final _builtinSkill = SkillModel(
    id: 'builtin_beginner_guide',
    name: '新手引导专家',
    content: '''你是一个极具耐心、温柔且专业的 GG-AI新手引导专家。

你的主要目标是帮助完全没有内存修改经验的新手，轻松、安心地学会使用本修改器修改单机游戏。

### 核心原则
- **极度友好与耐心**：用最简单易懂的语言，像教小白朋友一样一步一步讲解。
- **零基础假设**：默认用户完全不懂内存修改、GG、搜索等概念，每次都要解释清楚。
- **安全第一**：每一步重要操作前都必须提醒"请先备份存档"，并说明可能的风险。
- **只限单机**：一旦用户提到在线游戏，立刻温柔但坚定地拒绝，并解释原因。
- **逐步引导**：永远一次只教一个步骤，确认用户理解并成功后再进行下一步。
- **鼓励提问**：随时欢迎用户说"看不懂""不会操作""出了什么问题"等。

### 必须掌握并能清晰讲解的内容
1. 如何选择并附加游戏进程
2. 什么是精确搜索、模糊搜索、AOB
3. 如何搜索数值（已知数值 / 未知数值）
4. 搜索到结果后如何修改和冻结
5. 为什么推荐使用冻结功能
6. 如何保存地址和导出脚本
7. 常见问题处理（结果太多、地址失效、游戏崩溃等）

### 回复风格要求
- 使用**最白话的中文**，多用"咱们""现在我们来……""很简单，就是……"等语气。
- 大量使用编号步骤（1. 2. 3.）。
- 每一步操作后都要问："这一步成功了吗？""你看到什么结果？"
- 可以适当使用生活中的比喻（如"内存就像游戏的大脑，我们在里面找金币的存放位置"）。
- 回复中可使用 Markdown 列表、代码块，但不要使用过于复杂的表格。
- 结束时总是询问："下一步你想做什么？或者哪里还不明白？"

### 工作流程（新手版）
1. 先确认用户是否已打开游戏并进入对应界面。
2. 教用户如何附加进程。
3. 询问用户想修改什么（金币、生命、等级等）。
4. 根据目标给出最简单、最安全的修改方案。
5. 每步操作后等待用户反馈，再继续下一步。
6. 成功后教用户如何保存或做成一键脚本。

现在开始作为最贴心的新手引导专家，帮助用户从零学会内存修改！''',
    isBuiltin: true,
    isEnabled: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSkills();
    });
  }

  void _loadSkills() {
    final storage = ref.read(storageServiceProvider);
    final userSkills = storage.getAllSkills();

    // 读取内置 Skill 的启用状态
    final builtinEnabled = storage.getSetting('skill_${_builtinSkill.id}_enabled', defaultValue: false) as bool;
    final builtinWithState = _builtinSkill.copyWith(isEnabled: builtinEnabled);

    // 合并系统内置 Skill 和用户导入的 Skill
    final allSkills = <SkillModel>[builtinWithState];

    // 添加用户导入的 Skill（避免重复添加内置 Skill）
    for (final skill in userSkills) {
      if (skill.id != _builtinSkill.id) {
        allSkills.add(skill);
      }
    }

    ref.read(skillsProvider.notifier).state = allSkills;
  }

  /// 导入 Skill 文件
  Future<void> _importSkill() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String content;

      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        final fileObj = File(file.path!);
        content = await fileObj.readAsString();
      } else {
        _showSnackBar('❌ 无法读取文件');
        return;
      }

      if (!mounted) return;

      // 显示命名对话框
      _showNameDialog(content, file.name, file.path);
    } catch (e) {
      _showSnackBar('❌ 导入失败: $e');
    }
  }

  /// 显示命名对话框
  void _showNameDialog(String content, String fileName, String? filePath) {
    final nameController = TextEditingController(
      text: fileName.replaceAll('.md', ''),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('导入 Skill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Skill 名称',
                hintText: '输入显示名称',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description, size: 16, color: Color(0xFF4A6572)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                _showSnackBar('请输入名称');
                return;
              }
              _saveSkill(name, content, filePath);
              Navigator.pop(context);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  /// 保存 Skill
  Future<void> _saveSkill(String name, String content, String? filePath) async {
    final storage = ref.read(storageServiceProvider);
    final now = DateTime.now();

    // 复制文件到应用目录
    String savedPath = '';
    if (filePath != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final skillsDir = Directory('${appDir.path}/skills');
        if (!await skillsDir.exists()) {
          await skillsDir.create(recursive: true);
        }
        final skillFile = File('${skillsDir.path}/${now.millisecondsSinceEpoch}.md');
        await skillFile.writeAsString(content);
        savedPath = skillFile.path;
      } catch (e) {
        savedPath = filePath;
      }
    }

    final skill = SkillModel(
      id: 'skill_${now.millisecondsSinceEpoch}',
      name: name,
      content: content,
      filePath: savedPath,
      isEnabled: false,
      createdAt: now,
      updatedAt: now,
    );

    await storage.saveSkill(skill);
    _loadSkills();
    _showSnackBar('✅ Skill "$name" 已导入');
  }

  /// 删除 Skill
  void _deleteSkill(SkillModel skill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('删除 Skill'),
        content: Text('确定要删除 "${skill.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final storage = ref.read(storageServiceProvider);
              await storage.deleteSkill(skill.id);
              _loadSkills();
              Navigator.pop(context);
              _showSnackBar('✅ 已删除 "${skill.name}"');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 切换 Skill 启用状态
  Future<void> _toggleSkill(SkillModel skill) async {
    final storage = ref.read(storageServiceProvider);

    if (skill.isBuiltin) {
      // 内置 Skill 保存到设置中
      final newValue = !skill.isEnabled;
      await storage.saveSetting('skill_${skill.id}_enabled', newValue);
    } else {
      await storage.toggleSkill(skill.id);
    }

    _loadSkills();

    // 同步所有已启用的 Skill
    final allSkills = ref.read(skillsProvider);
    final enabledSkills = allSkills.where((s) => s.isEnabled).toList();
    _syncSkillsToNative(enabledSkills);
  }

  /// 同步 Skill 到原生层（供悬浮窗读取）
  void _syncSkillsToNative(List<SkillModel> enabledSkills) {
    try {
      final skillsJson = enabledSkills.map((s) => {
        'id': s.id,
        'name': s.name,
        'content': s.content,
      }).toList();
      const channel = MethodChannel('com.yl.aigg/bridge');
      channel.invokeMethod('syncSkills', {'skills': jsonEncode(skillsJson)});
    } catch (_) {}
  }

  /// 显示导出选择对话框
  void _showExportDialog() {
    final storage = ref.read(storageServiceProvider);
    final skills = storage.getAllSkills();

    if (skills.isEmpty) {
      _showSnackBar('没有可导出的 Skill');
      return;
    }

    final selectedToExport = <String>{};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          title: const Text('导出 Skill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: skills.map((skill) {
                return CheckboxListTile(
                  title: Text(skill.name),
                  subtitle: Text(
                    skill.isBuiltin ? '系统内置' : '用户导入',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
                  ),
                  value: selectedToExport.contains(skill.id),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedToExport.add(skill.id);
                      } else {
                        selectedToExport.remove(skill.id);
                      }
                    });
                  },
                  activeColor: const Color(0xFF3D5AFE),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedToExport.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);
                      _exportSelectedSkills(selectedToExport);
                    },
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
  }

  /// 导出选中的 Skill
  Future<void> _exportSelectedSkills(Set<String> selectedIds) async {
    final storage = ref.read(storageServiceProvider);
    final allSkills = storage.getAllSkills();
    final skillsToExport = allSkills.where((s) => selectedIds.contains(s.id)).toList();

    if (skillsToExport.isEmpty) return;

    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      int successCount = 0;

      for (final skill in skillsToExport) {
        final fileName = '${skill.name}.md';
        final filePath = await channel.invokeMethod('exportSkillToFile', {
          'fileName': fileName,
          'content': skill.content,
        });
        if (filePath != null) {
          successCount++;
        }
      }

      _showSnackBar('✅ 已导出 $successCount 个 Skill');
    } catch (e) {
      _showSnackBar('❌ 导出失败: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skills = ref.watch(skillsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F8),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.extension, color: Color(0xFF3D5AFE)),
            SizedBox(width: 8),
            Text('插件中心'),
          ],
        ),
        actions: [
          // 导出按钮
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: '导出 Skill',
            onPressed: _showExportDialog,
          ),
          // 添加按钮
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '导入 Skill',
            onPressed: _importSkill,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF3D5AFE).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, color: Color(0xFF3D5AFE), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Skill 管理中心',
                          style: TextStyle(
                            color: Color(0xFF213333),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '已导入 ${skills.length} 个 Skill，${skills.where((s) => s.isEnabled).length} 个已启用',
                          style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Skill 列表标题
            Row(
              children: [
                const Text(
                  '📋 已导入的 Skill',
                  style: TextStyle(
                    color: Color(0xFF213333),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '点击开关启用/禁用',
                  style: TextStyle(
                    color: const Color(0xFF4A6572).withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Skill 列表
            Expanded(
              child: skills.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.extension_off_outlined,
                            size: 64,
                            color: const Color(0xFF4A6572).withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '暂无 Skill',
                            style: TextStyle(color: Color(0xFF4A6572), fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '点击右上角 + 导入 .md 文件',
                            style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: skills.length,
                      itemBuilder: (context, index) {
                        return _buildSkillCard(skills[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCard(SkillModel skill) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: skill.isEnabled
                    ? const Color(0xFF3D5AFE).withOpacity(0.1)
                    : const Color(0xFFF2F3F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                skill.isBuiltin ? Icons.school : Icons.description,
                color: skill.isEnabled
                    ? const Color(0xFF3D5AFE)
                    : const Color(0xFF4A6572),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // 名称和信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        skill.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: skill.isEnabled
                              ? const Color(0xFF213333)
                              : const Color(0xFF4A6572),
                        ),
                      ),
                      if (skill.isBuiltin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3D5AFE).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '系统内置',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF3D5AFE),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${skill.content.length} 字符 · ${skill.isEnabled ? "已启用" : "未启用"}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4A6572),
                    ),
                  ),
                ],
              ),
            ),

            // 开关
            Switch(
              value: skill.isEnabled,
              onChanged: (_) => _toggleSkill(skill),
              activeColor: const Color(0xFF3D5AFE),
            ),

            // 删除按钮（内置 Skill 不显示）
            if (!skill.isBuiltin)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: const Color(0xFF4A6572),
              onPressed: () => _deleteSkill(skill),
            ),
          ],
        ),
      ),
    );
  }
}
