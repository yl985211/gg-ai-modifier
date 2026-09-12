/// 脚本库页面
/// 支持脚本持久化存储、通过 LuaJ 执行 Lua 脚本、运行日志管理

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/script_model.dart';
import '../../main.dart';

/// 脚本列表 Provider
final scriptsProvider = StateProvider<List<ScriptModel>>((ref) => []);

/// 运行日志 Provider
final scriptLogsProvider = StateProvider<List<Map<String, String>>>(
  (ref) => [],
);

/// 脚本库页面
class ScriptPage extends ConsumerStatefulWidget {
  const ScriptPage({super.key});

  @override
  ConsumerState<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends ConsumerState<ScriptPage> {
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScripts();
      _loadLogs();
    });
  }

  /// 加载脚本（内置 + 用户保存的）
  void _loadScripts() {
    final storage = ref.read(storageServiceProvider);
    final savedScripts = storage.getAllScripts();

    final builtinScripts = [
      ScriptModel(
        id: 'builtin_test',
        name: '运行测试',
        description: 'Lua 菜单弹窗 + 数据搜索测试脚本',
        content: _builtinTestScript,
        isBuiltin: true,
        tags: ['测试', '菜单'],
      ),
    ];

    final mergedMap = <String, ScriptModel>{};
    for (final s in builtinScripts) {
      mergedMap[s.id] = s;
    }
    for (final s in savedScripts) {
      mergedMap[s.id] = s;
    }

    ref.read(scriptsProvider.notifier).state = mergedMap.values.toList();

    // 同步脚本到 SharedPreferences（供悬浮窗读取）
    _syncScriptsToNative(mergedMap.values.toList());
  }

  /// 同步脚本到原生层
  void _syncScriptsToNative(List<ScriptModel> scripts) {
    try {
      final scriptsJson = scripts
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'content': s.content,
              'description': s.description,
            },
          )
          .toList();
      const channel = MethodChannel('com.yl.aigg/bridge');
      channel.invokeMethod('syncScripts', {'scripts': jsonEncode(scriptsJson)});
    } catch (_) {}
  }

  /// 加载运行日志（合并 Hive 存储 + 悬浮窗 SharedPreferences 存储）
  void _loadLogs() {
    final storage = ref.read(storageServiceProvider);
    final allLogs = <Map<String, String>>[];

    // 1. 从 Hive 读取（主应用保存的日志）
    try {
      final logsJson =
          storage.getSetting('script_logs', defaultValue: '[]') as String;
      final List<dynamic> decoded = jsonDecode(logsJson);
      for (final e in decoded) {
        allLogs.add(Map<String, String>.from(e as Map));
      }
    } catch (_) {}

    // 2. 从 SharedPreferences 读取（悬浮窗保存的日志）
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      channel
          .invokeMethod('getOverlayScriptLogs')
          .then((result) {
            if (result != null && result is List) {
              for (final log in result) {
                if (log is Map) {
                  final logMap = Map<String, String>.from(log);
                  // 去重：检查是否已存在同名日志
                  final exists = allLogs.any(
                    (l) => l['name'] == logMap['name'],
                  );
                  if (!exists) {
                    allLogs.add(logMap);
                  }
                }
              }
            }
            // 按时间倒序排列
            allLogs.sort(
              (a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''),
            );
            ref.read(scriptLogsProvider.notifier).state = allLogs;
          })
          .catchError((_) {
            allLogs.sort(
              (a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''),
            );
            ref.read(scriptLogsProvider.notifier).state = allLogs;
          });
    } catch (_) {
      allLogs.sort((a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''));
      ref.read(scriptLogsProvider.notifier).state = allLogs;
    }
  }

  /// 保存运行日志
  Future<void> _saveLog(String scriptName, String output) async {
    final storage = ref.read(storageServiceProvider);
    final now = DateTime.now();
    final timeStr =
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final logName = '${timeStr}_$scriptName';

    final currentLogs = ref.read(scriptLogsProvider);
    final newLog = {
      'name': logName,
      'scriptName': scriptName,
      'time': now.toIso8601String(),
      'output': output,
    };
    final updatedLogs = [newLog, ...currentLogs];
    ref.read(scriptLogsProvider.notifier).state = updatedLogs;

    // 持久化保存
    await storage.saveSetting('script_logs', jsonEncode(updatedLogs));
  }

  /// 运行脚本
  Future<void> _runScript(ScriptModel script) async {
    if (_isRunning) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('⚠️ 已有脚本正在执行')));
      return;
    }

    setState(() {
      _isRunning = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('🚀 正在运行: ${script.name}')));

    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final result = await channel.invokeMethod('executeLuaScript', {
        'scriptId': script.id,
        'scriptContent': script.content,
      });

      final output = result?.toString() ?? '执行完成';

      // 自动保存日志
      await _saveLog(script.name, output);

      // 更新执行次数
      final scripts = ref.read(scriptsProvider);
      final updatedScripts = scripts.map((s) {
        if (s.id == script.id) {
          return s.copyWith(
            executionCount: s.executionCount + 1,
            lastExecutedAt: DateTime.now(),
          );
        }
        return s;
      }).toList();
      ref.read(scriptsProvider.notifier).state = updatedScripts;

      setState(() {
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ ${script.name} 执行完成，日志已保存')));
      }
    } catch (e) {
      final errorOutput = '执行失败: $e';
      await _saveLog(script.name, errorOutput);

      setState(() {
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 执行失败: $e')));
      }
    }
  }

  /// 刷新脚本和日志
  void _refresh() {
    _loadScripts();
    _loadLogs();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 已刷新脚本列表和运行日志'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scripts = ref.watch(scriptsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.code, color: Color(0xFF3D5AFE)),
            SizedBox(width: 8),
            Text('脚本库'),
          ],
        ),
        actions: [
          // 脚本运行日志按钮
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: '脚本运行日志',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScriptLogPage()),
              );
            },
          ),
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新脚本列表',
            onPressed: _refresh,
          ),
          // 添加按钮
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '创建新脚本',
            onPressed: () {
              _showCreateScriptDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 运行状态
          if (_isRunning)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFFFFF),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('脚本运行中...', style: TextStyle(color: Colors.orange)),
                ],
              ),
            ),
          // 脚本列表
          Expanded(
            child: scripts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.code_off, size: 64, color: Color(0xFF4A6572)),
                        SizedBox(height: 16),
                        Text('暂无脚本', style: TextStyle(color: Color(0xFF4A6572))),
                        SizedBox(height: 8),
                        Text(
                          '点击右上角 + 创建新脚本',
                          style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: scripts.length,
                    itemBuilder: (context, index) {
                      return _buildScriptCard(scripts[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptCard(ScriptModel script) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          _showScriptDetail(script);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    script.isBuiltin
                        ? Icons.inventory_2
                        : script.isAiGenerated
                        ? Icons.smart_toy
                        : Icons.person,
                    color: script.isBuiltin
                        ? const Color(0xFF536DFE)
                        : script.isAiGenerated
                        ? const Color(0xFF3D5AFE)
                        : Color(0xFF4A6572),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      script.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'run',
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow, size: 16),
                            SizedBox(width: 8),
                            Text('运行'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 16),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      if (!script.isBuiltin)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'run':
                          _runScript(script);
                          break;
                        case 'edit':
                          _showScriptEditor(script);
                          break;
                        case 'delete':
                          _deleteScript(script);
                          break;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                script.description,
                style: const TextStyle(color: Color(0xFF4A6572), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ...script.tags.map(
                    (tag) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D5AFE).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3D5AFE),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (script.executionCount > 0)
                    Text(
                      '已执行 ${script.executionCount} 次',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF4A6572)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScriptDetail(ScriptModel script) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF2F3F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Color(0xFF4A6572),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      script.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _runScript(script);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('运行'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    script.content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFF536DFE),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showScriptEditor(ScriptModel? script) {
    final nameController = TextEditingController(text: script?.name ?? '');
    final descController = TextEditingController(
      text: script?.description ?? '',
    );
    final contentController = TextEditingController(
      text: script?.content ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: Text(script == null ? '创建脚本' : '编辑脚本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '脚本名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '描述'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Lua 代码',
                  alignLabelWithHint: true,
                ),
                maxLines: 10,
                minLines: 5,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final desc = descController.text.trim();
              final content = contentController.text.trim();

              if (name.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入脚本名称')));
                return;
              }
              if (content.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入脚本内容')));
                return;
              }

              final storage = ref.read(storageServiceProvider);
              final scripts = ref.read(scriptsProvider);

              if (script != null) {
                final updated = script.copyWith(
                  name: name,
                  description: desc,
                  content: content,
                  updatedAt: DateTime.now(),
                );
                ref.read(scriptsProvider.notifier).state = scripts.map((s) {
                  return s.id == script.id ? updated : s;
                }).toList();
                await storage.saveScript(updated);
              } else {
                final newScript = ScriptModel(
                  id: 'user_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  description: desc,
                  content: content,
                );
                ref.read(scriptsProvider.notifier).state = [
                  ...scripts,
                  newScript,
                ];
                await storage.saveScript(newScript);
              }

              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('✅ 脚本已保存: $name')));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showCreateScriptDialog() {
    _showScriptEditor(null);
  }

  void _deleteScript(ScriptModel script) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('删除脚本'),
        content: Text('确定要删除 "${script.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final scripts = ref.read(scriptsProvider);
              ref.read(scriptsProvider.notifier).state = scripts
                  .where((s) => s.id != script.id)
                  .toList();
              final storage = ref.read(storageServiceProvider);
              await storage.deleteScript(script.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ==================== 内置脚本 ====================

  static const String _builtinTestScript = '''
-- ============================================
-- 游戏修改器 Lua 测试脚本
-- 功能：菜单弹窗 + 数据搜索测试
-- ============================================

-- ====== 搜索数据函数 ======
function searchData(value, valueType)
    gg.clearResults()
    gg.searchNumber(value, valueType)
    local count = gg.getResultCount()
    gg.toast("搜索完成，找到 " .. count .. " 条结果")
    return count
end

-- ====== 二级菜单1：数值搜索 ======
function menu1_search()
    local choice = gg.choice({
        " 搜索整数 9999",
        " 搜索浮点 1.0",
        " 搜索双精度 3.14"
    }, nil, "【数值搜索】请选择搜索类型")

    if choice == nil then
        gg.toast("已取消")
        return
    end

    if choice == 1 then
        searchData(9999, gg.TYPE_DWORD)
        gg.toast("搜索整数 9999 完成")
    elseif choice == 2 then
        searchData("1.0", gg.TYPE_FLOAT)
        gg.toast("搜索浮点 1.0 完成")
    elseif choice == 3 then
        searchData("3.14", gg.TYPE_DOUBLE)
        gg.toast("搜索双精度 3.14 完成")
    end
end

-- ====== 二级菜单2：高级操作 ======
function menu2_advanced()
    local choice = gg.choice({
        " 修改搜索结果为 88888",
        " 冻结当前结果",
        " 清除所有结果"
    }, nil, "【高级操作】请选择操作")

    if choice == nil then
        gg.toast("已取消")
        return
    end

    if choice == 1 then
        local count = gg.getResultCount()
        if count > 0 then
            local results = gg.getResults(count)
            for i, v in ipairs(results) do
                results[i].value = 88888
                results[i].flags = gg.TYPE_DWORD
            end
            gg.setValues(results)
            gg.toast("已修改 " .. count .. " 条数据为 88888")
        else
            gg.toast("没有搜索结果，请先搜索数据")
        end
    elseif choice == 2 then
        local count = gg.getResultCount()
        if count > 0 then
            local results = gg.getResults(count)
            for i, v in ipairs(results) do
                results[i].freeze = true
            end
            gg.addListItems(results)
            gg.toast("已冻结 " .. count .. " 条数据")
        else
            gg.toast("没有搜索结果，请先搜索数据")
        end
    elseif choice == 3 then
        gg.clearResults()
        gg.clearList()
        gg.toast("已清除所有结果和冻结列表")
    end
end

-- ====== 主菜单 ======
function mainMenu()
    while true do
        local main = gg.choice({
            " 数值搜索",
            " 高级操作",
            " 退出脚本"
        }, nil, "=== Lua 测试脚本 v1.0 ===")

        if main == nil or main == 3 then
            gg.toast("脚本已退出")
            break
        elseif main == 1 then
            menu1_search()
        elseif main == 2 then
            menu2_advanced()
        end
    end
end

-- ====== 启动 ======
gg.toast("Lua 测试脚本已加载 ")
gg.sleep(1000)
mainMenu()
''';
}

/// 脚本运行日志页面
class ScriptLogPage extends ConsumerStatefulWidget {
  const ScriptLogPage({super.key});

  @override
  ConsumerState<ScriptLogPage> createState() => _ScriptLogPageState();
}

class _ScriptLogPageState extends ConsumerState<ScriptLogPage> {
  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(scriptLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Color(0xFF3D5AFE)),
            SizedBox(width: 8),
            Text('脚本运行日志'),
          ],
        ),
        actions: [
          // 清空日志
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空所有日志',
            onPressed: logs.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFFFFFFFF),
                        title: const Text('清空日志'),
                        content: const Text('确定要清空所有运行日志吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      ref.read(scriptLogsProvider.notifier).state = [];
                      final storage = ref.read(storageServiceProvider);
                      await storage.saveSetting('script_logs', '[]');
                    }
                  },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Color(0xFF4A6572)),
                  SizedBox(height: 16),
                  Text('暂无运行日志', style: TextStyle(color: Color(0xFF4A6572))),
                  SizedBox(height: 8),
                  Text(
                    '运行脚本后会自动保存日志',
                    style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return _buildLogCard(log);
              },
            ),
    );
  }

  Widget _buildLogCard(Map<String, String> log) {
    final name = log['name'] ?? '未知';
    final scriptName = log['scriptName'] ?? '未知';
    final time = log['time'] ?? '';
    final output = log['output'] ?? '';

    // 格式化时间显示
    String formattedTime = '';
    try {
      final dt = DateTime.parse(time);
      formattedTime =
          '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      formattedTime = time;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFFFFFFFF),
      child: InkWell(
        onTap: () {
          _showLogDetail(log);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description,
                    color: Color(0xFF3D5AFE),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () async {
                      final logs = ref.read(scriptLogsProvider);
                      ref.read(scriptLogsProvider.notifier).state = logs
                          .where((l) => l['name'] != name)
                          .toList();
                      final storage = ref.read(storageServiceProvider);
                      await storage.saveSetting(
                        'script_logs',
                        jsonEncode(ref.read(scriptLogsProvider)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '脚本: $scriptName',
                    style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time, size: 12, color: Color(0xFF4A6572)),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  output.length > 150
                      ? '${output.substring(0, 150)}...'
                      : output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF536DFE),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogDetail(Map<String, String> log) {
    final name = log['name'] ?? '未知';
    final output = log['output'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF2F3F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Color(0xFF4A6572),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: '复制日志',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: output));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ 日志已复制到剪贴板')),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFF536DFE),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
