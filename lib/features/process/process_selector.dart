/// 进程选择器页面
/// 扫描运行中的进程并允许用户选择目标游戏

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/process_info.dart';

/// 当前附加的进程 Provider
final attachedProcessProvider = StateProvider<ProcessInfo?>((ref) => null);

/// 进程列表 Provider
final processListProvider = StateProvider<List<ProcessInfo>>((ref) => []);

/// 进程选择器页面
class ProcessSelectorPage extends ConsumerStatefulWidget {
  const ProcessSelectorPage({super.key});

  @override
  ConsumerState<ProcessSelectorPage> createState() =>
      _ProcessSelectorPageState();
}

class _ProcessSelectorPageState extends ConsumerState<ProcessSelectorPage> {
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProcessList();
    _checkAttachedProcess();
  }

  Future<void> _checkAttachedProcess() async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final pid = await channel.invokeMethod('getAttachedPid');
      
      if (pid != null && pid > 0 && mounted) {
        // 有附加的进程，获取进程信息
        final result = await channel.invokeMethod('getProcessList');
        if (result != null) {
          final List<dynamic> list = result as List<dynamic>;
          final processes = list.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return ProcessInfo.fromJson(map);
          }).toList();
          
          // 找到对应的进程
          final attachedProcess = processes.firstWhere(
            (p) => p.pid == pid,
            orElse: () => processes.first,
          );
          
          if (mounted) {
            ref.read(attachedProcessProvider.notifier).state = attachedProcess;
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProcessList() async {
    setState(() => _isLoading = true);

    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final result = await channel.invokeMethod('getProcessList');

      if (result != null && mounted) {
        final List<dynamic> list = result as List<dynamic>;
        final processes = list.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ProcessInfo.fromJson(map);
        }).toList();

        // 过滤掉系统进程，只显示应用进程
        final appProcesses = processes
            .where(
              (p) =>
                  !p.isSystem &&
                  p.packageName.isNotEmpty &&
                  !p.packageName.startsWith('com.android.') &&
                  !p.packageName.startsWith('android.') &&
                  p.packageName != 'system' &&
                  p.packageName != 'zygote' &&
                  p.packageName != 'zygote64' &&
                  p.packageName.contains('.'),
            )
            .toList();

        if (mounted) {
          ref.read(processListProvider.notifier).state = appProcesses;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取进程列表失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _attachProcess(ProcessInfo process) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final result = await channel.invokeMethod('attachProcess', {
        'pid': process.pid,
      });

      if (result == true && mounted) {
        ref.read(attachedProcessProvider.notifier).state = process;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已附加到 ${process.displayName}')),
        );
        Navigator.pop(context, process);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('❌ 附加进程失败')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 附加进程失败: $e')));
      }
    }
  }

  List<ProcessInfo> get _filteredProcesses {
    final processes = ref.read(processListProvider);
    if (_searchQuery.isEmpty) return processes;
    return processes
        .where(
          (p) =>
              p.displayName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              p.packageName.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final attachedProcess = ref.watch(attachedProcessProvider);
    final processes = ref.watch(processListProvider);
    final filteredProcesses = _filteredProcesses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择游戏进程'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadProcessList,
          ),
        ],
      ),
      body: Column(
        children: [
          // 当前附加状态
          if (attachedProcess != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFFFFF),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前附加: ${attachedProcess.displayName}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${attachedProcess.packageName} (PID: ${attachedProcess.pid})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A6572),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        const channel = MethodChannel('com.yl.aigg/bridge');
                        await channel.invokeMethod('detachProcess');
                        ref.read(attachedProcessProvider.notifier).state = null;
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已分离进程')),
                          );
                        }
                      } catch (_) {}
                    },
                    child: const Text(
                      '分离',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索游戏名称或包名...',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // 进程数量
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '找到 ${filteredProcesses.length} 个应用进程',
                  style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 进程列表
          Expanded(
            child: _isLoading && processes.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在扫描进程...', style: TextStyle(color: Color(0xFF4A6572))),
                      ],
                    ),
                  )
                : filteredProcesses.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apps, size: 64, color: Color(0xFF4A6572)),
                        SizedBox(height: 16),
                        Text('未找到应用进程', style: TextStyle(color: Color(0xFF4A6572))),
                        SizedBox(height: 8),
                        Text(
                          '请确保已打开游戏应用',
                          style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredProcesses.length,
                    itemBuilder: (context, index) {
                      final process = filteredProcesses[index];
                      final isAttached = attachedProcess?.pid == process.pid;

                      return ListTile(
                        leading: Icon(
                          isAttached ? Icons.check_circle : Icons.apps,
                          color: isAttached
                              ? Colors.green
                              : const Color(0xFF3D5AFE),
                        ),
                        title: Text(
                          process.displayName,
                          style: TextStyle(
                            fontWeight: isAttached
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${process.packageName}  |  PID: ${process.pid}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4A6572),
                          ),
                        ),
                        trailing: isAttached
                            ? const Chip(
                                label: Text(
                                  '已附加',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF213333),
                                  ),
                                ),
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.zero,
                              )
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: isAttached
                            ? null
                            : () => _attachProcess(process),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
