/// 游戏选择器组件
/// 显示运行中的进程列表，允许用户选择目标游戏

import 'package:flutter/material.dart';
import '../core/models/process_info.dart';

/// 游戏选择器组件
class GameSelector extends StatefulWidget {
  /// 进程列表
  final List<ProcessInfo> processes;

  /// 选中回调
  final ValueChanged<ProcessInfo>? onSelected;

  /// 当前选中的进程
  final ProcessInfo? selectedProcess;

  /// 是否正在加载
  final bool isLoading;

  /// 刷新回调
  final VoidCallback? onRefresh;

  const GameSelector({
    super.key,
    required this.processes,
    this.onSelected,
    this.selectedProcess,
    this.isLoading = false,
    this.onRefresh,
  });

  @override
  State<GameSelector> createState() => _GameSelectorState();
}

class _GameSelectorState extends State<GameSelector> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProcessInfo> get _filteredProcesses {
    if (_searchQuery.isEmpty) return widget.processes;
    return widget.processes.where((p) {
      return p.packageName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.processName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索游戏...',
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: widget.onRefresh != null
                  ? IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      onPressed: widget.onRefresh,
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),

        // 当前选中
        if (widget.selectedProcess != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3D5AFE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF3D5AFE).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF3D5AFE),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.selectedProcess!.packageName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'PID: ${widget.selectedProcess!.pid}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A6572),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // 进程列表
        if (widget.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else if (_filteredProcesses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('未找到进程', style: TextStyle(color: Color(0xFF4A6572))),
          )
        else
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: _filteredProcesses.length,
              itemBuilder: (context, index) {
                final process = _filteredProcesses[index];
                final isSelected = widget.selectedProcess?.pid == process.pid;

                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.apps,
                    color: isSelected ? const Color(0xFF3D5AFE) : Color(0xFF4A6572),
                    size: 20,
                  ),
                  title: Text(
                    process.packageName,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'PID: ${process.pid}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
                  ),
                  trailing: process.isSystem
                      ? const Chip(
                          label: Text('系统', style: TextStyle(fontSize: 10)),
                          backgroundColor: Colors.orange,
                          padding: EdgeInsets.zero,
                        )
                      : null,
                  onTap: () {
                    widget.onSelected?.call(process);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
