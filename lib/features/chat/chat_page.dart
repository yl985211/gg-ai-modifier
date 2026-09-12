/// AI 对话记录页面
/// 显示历史对话记录，管理对话历史
/// 支持加载悬浮窗保存的聊天记录
/// 支持单条/多条导出为 Markdown 文件

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_session.dart';
import '../../main.dart';
import '../process/process_selector.dart';
import 'markdown_webview.dart';

/// 聊天消息列表 Provider
final chatMessagesProvider = StateProvider<List<ChatMessage>>((ref) => []);

/// 聊天会话列表 Provider
final chatSessionsProvider = StateProvider<List<ChatSession>>((ref) => []);

/// AI 对话记录页面
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  /// 多选模式
  bool _isMultiSelectMode = false;
  final Set<String> _selectedSessionIds = {};

  @override
  void initState() {
    super.initState();
    _loadChatSessions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadSessions();
  }

  void _reloadSessions() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final storage = ref.read(storageServiceProvider);
      final savedSessions = storage.getAllSessions();
      final currentSessions = ref.read(chatSessionsProvider);

      final mergedMap = <String, ChatSession>{};
      for (final s in currentSessions) {
        mergedMap[s.id] = s;
      }
      for (final s in savedSessions) {
        mergedMap[s.id] = s;
      }

      // 同时加载悬浮窗保存的聊天记录（使用正确的时间戳）
      try {
        const channel = MethodChannel('com.yl.aigg/bridge');
        final result = await channel.invokeMethod('getOverlayChats');
        if (result != null && result is List) {
          for (final chatData in result) {
            if (chatData is! Map) continue;
            final chatId = chatData['id'] as String? ?? '';
            // 已存在于 mergedMap 中的跳过
            if (mergedMap.containsKey(chatId)) continue;

            DateTime? sessionTime;
            if (chatId.startsWith('chat_')) {
              final ms = int.tryParse(chatId.substring(5));
              if (ms != null) sessionTime = DateTime.fromMillisecondsSinceEpoch(ms);
            }

            final messages = <ChatMessage>[];
            final chatMessages = chatData['messages'] as List? ?? [];
            for (final msg in chatMessages) {
              if (msg is! Map) continue;
              final sender = msg['sender'] as String? ?? '';
              final message = msg['message'] as String? ?? '';
              final tsMs = msg['timestamp'] as int?;
              final msgTime = tsMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(tsMs)
                  : sessionTime;
              final isUser = sender.contains('我');
              if (isUser) {
                messages.add(ChatMessage.user(message).copyWith(timestamp: msgTime));
              } else {
                messages.add(ChatMessage.assistant(message).copyWith(timestamp: msgTime));
              }
            }

            if (messages.isNotEmpty) {
              final session = ChatSession.fromMessages(messages).copyWith(id: chatId);
              mergedMap[session.id] = session;
              // 持久化到 Hive
              await storage.saveSession(session);
            }
          }
        }
      } catch (_) {}

      final merged = mergedMap.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      ref.read(chatSessionsProvider.notifier).state = merged;
    });
  }

  void _loadChatSessions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final storage = ref.read(storageServiceProvider);
      final savedSessions = storage.getAllSessions();
      _loadOverlayChats(savedSessions);
      if (savedSessions.isNotEmpty) {
        ref.read(chatSessionsProvider.notifier).state = savedSessions;
      }
    });
  }

  /// 加载悬浮窗保存的聊天记录
  Future<void> _loadOverlayChats(List<ChatSession> existingSessions) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final result = await channel.invokeMethod('getOverlayChats');
      if (result == null || result is! List || result.isEmpty) return;

      final storage = ref.read(storageServiceProvider);
      final existingIds = existingSessions.map((s) => s.id).toSet();
      final overlaySessions = <ChatSession>[];

      for (final chatData in result) {
        if (chatData is! Map) continue;
        final chatId = chatData['id'] as String? ?? '';
        // 已存在于 Hive 中的跳过，避免重复
        if (existingIds.contains(chatId)) continue;

        // 从 session ID 提取保存时间作为 fallback（chat_1748501234567 → 1748501234567）
        DateTime? sessionTime;
        if (chatId.startsWith('chat_')) {
          final ms = int.tryParse(chatId.substring(5));
          if (ms != null) sessionTime = DateTime.fromMillisecondsSinceEpoch(ms);
        }

        final messages = <ChatMessage>[];
        final chatMessages = chatData['messages'] as List? ?? [];
        for (final msg in chatMessages) {
          if (msg is! Map) continue;
          final sender = msg['sender'] as String? ?? '';
          final message = msg['message'] as String? ?? '';
          final tsMs = msg['timestamp'] as int?;
          final msgTime = tsMs != null
              ? DateTime.fromMillisecondsSinceEpoch(tsMs)
              : sessionTime;
          final isUser = sender.contains('我');
          if (isUser) {
            messages.add(ChatMessage.user(message).copyWith(timestamp: msgTime));
          } else {
            messages.add(ChatMessage.assistant(message).copyWith(timestamp: msgTime));
          }
        }

        if (messages.isNotEmpty) {
          final session = ChatSession.fromMessages(messages).copyWith(id: chatId);
          overlaySessions.add(session);
        }
      }

      if (overlaySessions.isNotEmpty && mounted) {
        // 持久化到 Hive，确保重启后时间戳不丢失
        for (final s in overlaySessions) {
          await storage.saveSession(s);
        }
        final current = ref.read(chatSessionsProvider);
        final merged = [...overlaySessions, ...current]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        ref.read(chatSessionsProvider.notifier).state = merged;
      }
    } catch (_) {}
  }

  /// 清空所有记录
  void _clearAllSessions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('清空所有记录'),
        content: const Text('确定要清空所有对话记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              ref.read(chatSessionsProvider.notifier).state = [];
              final storage = ref.read(storageServiceProvider);
              await storage.clearAllSessions();
              await storage.clearChatHistory();
              try {
                const channel = MethodChannel('com.yl.aigg/bridge');
                await channel.invokeMethod('clearOverlayChats');
              } catch (_) {}
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('✅ 所有对话记录已清空')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 生成 Markdown 内容
  String _generateMarkdown(ChatSession session) {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln();
    buffer.writeln('> 创建时间: ${session.createdAt.toString().substring(0, 19)}');
    buffer.writeln('> 更新时间: ${session.updatedAt.toString().substring(0, 19)}');
    buffer.writeln('> ${session.summary}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in session.messages) {
      if (msg.isUser) {
        buffer.writeln('## 👤 用户');
      } else {
        buffer.writeln('## 🤖 GG-AI');
      }
      buffer.writeln();
      buffer.writeln(msg.content);
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    buffer.writeln('*导出时间: ${DateTime.now().toString().substring(0, 19)}*');
    return buffer.toString();
  }

  /// 导出单条会话到文件
  Future<void> _exportSingleSession(ChatSession session) async {
    try {
      final markdown = _generateMarkdown(session);
      final safeTitle = session.title.replaceAll(
        RegExp(r'[^\w\u4e00-\u9fa5]'),
        '_',
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeTitle}_$timestamp.md';

      const channel = MethodChannel('com.yl.aigg/bridge');
      final filePath = await channel.invokeMethod('exportChatToFile', {
        'fileName': fileName,
        'content': markdown,
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ 已导出到: $filePath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 导出失败: $e')));
      }
    }
  }

  /// 导出多条会话到文件
  Future<void> _exportMultipleSessions(List<ChatSession> sessions) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('# GG-AI 对话记录批量导出');
      buffer.writeln();
      buffer.writeln('> 导出时间: ${DateTime.now().toString().substring(0, 19)}');
      buffer.writeln('> 共 ${sessions.length} 个会话');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();

      for (int i = 0; i < sessions.length; i++) {
        buffer.writeln(_generateMarkdown(sessions[i]));
        if (i < sessions.length - 1) {
          buffer.writeln('\n\n');
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'GG-AI_批量导出_$timestamp.md';

      const channel = MethodChannel('com.yl.aigg/bridge');
      final filePath = await channel.invokeMethod('exportChatToFile', {
        'fileName': fileName,
        'content': buffer.toString(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已导出 ${sessions.length} 个会话到: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 导出失败: $e')));
      }
    }
  }

  /// 显示导出选项对话框
  void _showExportDialog() {
    final sessions = ref.read(chatSessionsProvider);
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有对话记录可导出')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('导出对话记录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.file_download,
                color: Color(0xFF3D5AFE),
              ),
              title: const Text('导出全部到文件'),
              subtitle: Text('将 ${sessions.length} 个会话导出为 Markdown 文件'),
              onTap: () {
                Navigator.pop(context);
                _exportMultipleSessions(sessions);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist, color: Color(0xFF536DFE)),
              title: const Text('选择导出'),
              subtitle: const Text('选择要导出的会话'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isMultiSelectMode = true;
                  _selectedSessionIds.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新会话列表
  void _refreshSessions() {
    _reloadSessions();
    // 延迟显示提示，等待异步加载完成
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        final sessions = ref.read(chatSessionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已刷新，共 ${sessions.length} 个会话'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    });
  }

  void _viewSession(ChatSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSessionDetailPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(chatSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelectMode
            ? Text('已选择 ${_selectedSessionIds.length} 项')
            : const Row(
                children: [
                  Icon(Icons.history, color: Color(0xFF3D5AFE)),
                  SizedBox(width: 8),
                  Text('对话记录'),
                ],
              ),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isMultiSelectMode = false;
                    _selectedSessionIds.clear();
                  });
                },
              )
            : null,
        actions: _isMultiSelectMode
            ? [
                // 全选/取消全选
                IconButton(
                  icon: Icon(
                    _selectedSessionIds.length == sessions.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  tooltip: _selectedSessionIds.length == sessions.length
                      ? '取消全选'
                      : '全选',
                  onPressed: () {
                    setState(() {
                      if (_selectedSessionIds.length == sessions.length) {
                        _selectedSessionIds.clear();
                      } else {
                        _selectedSessionIds.addAll(sessions.map((s) => s.id));
                      }
                    });
                  },
                ),
                // 导出选中项
                IconButton(
                  icon: const Icon(Icons.file_download),
                  tooltip: '导出选中项',
                  onPressed: _selectedSessionIds.isEmpty
                      ? null
                      : () {
                          final selected = sessions
                              .where((s) => _selectedSessionIds.contains(s.id))
                              .toList();
                          setState(() {
                            _isMultiSelectMode = false;
                            _selectedSessionIds.clear();
                          });
                          _exportMultipleSessions(selected);
                        },
                ),
              ]
            : [
                // 刷新按钮
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新对话记录',
                  onPressed: _refreshSessions,
                ),
                // 导出按钮
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: '导出对话记录',
                  onPressed: _showExportDialog,
                ),
                // 清空按钮
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: '清空所有记录',
                  onPressed: _clearAllSessions,
                ),
                // 悬浮窗按钮
                IconButton(
                  icon: const Icon(Icons.chat_bubble),
                  tooltip: '启动悬浮窗对话',
                  onPressed: () {
                    const channel = MethodChannel('com.yl.aigg/bridge');
                    channel.invokeMethod('startOverlay');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('💡 悬浮窗已启动，点击悬浮球 → AI 对话'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          // 功能说明卡片
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF3D5AFE).withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF3D5AFE),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '使用说明',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D5AFE),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '• 实时对话：使用悬浮窗中的 AI 对话功能\n'
                  '• 历史记录：在此页面查看所有对话历史\n'
                  '• 游戏中使用：悬浮窗更适合游戏内快速对话\n'
                  '• 手动刷新：悬浮窗保存聊天后，点击右上角 🔄 刷新按钮\n'
                  '• 导出记录：仅支持单条记录导出为 Markdown 文件\n'
                  '• 导出路径：安卓10 /AI-gg/  安卓11+ /Documents/AI-gg/',
                  style: TextStyle(color: Color(0xFF4A6572), fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          const channel = MethodChannel('com.yl.aigg/bridge');
                          channel.invokeMethod('startOverlay');
                        },
                        icon: const Icon(Icons.chat_bubble, size: 16),
                        label: const Text('启动悬浮窗对话'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3D5AFE),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 会话列表
          Expanded(
            child: sessions.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Color(0xFF4A6572)),
                        SizedBox(height: 16),
                        Text('暂无对话记录', style: TextStyle(color: Color(0xFF4A6572))),
                        SizedBox(height: 8),
                        Text(
                          '使用悬浮窗开始与 AI 对话',
                          style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _buildSessionCard(session);
                    },
                  ),
          ),

          // 统计信息
          if (sessions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFFFFF),
              child: Row(
                children: [
                  const Icon(Icons.analytics, size: 16, color: Color(0xFF4A6572)),
                  const SizedBox(width: 8),
                  Text(
                    '共 ${sessions.length} 个对话会话',
                    style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '最后更新: ${DateTime.now().toString().substring(0, 16)}',
                    style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(ChatSession session) {
    final isSelected = _selectedSessionIds.contains(session.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? const Color(0xFF3D5AFE).withOpacity(0.15)
          : const Color(0xFFFFFFFF),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: _isMultiSelectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedSessionIds.add(session.id);
                    } else {
                      _selectedSessionIds.remove(session.id);
                    }
                  });
                },
                activeColor: const Color(0xFF3D5AFE),
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D5AFE).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getSessionIcon(session.title),
                  color: const Color(0xFF3D5AFE),
                  size: 24,
                ),
              ),
        title: Text(
          session.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              session.previewText,
              style: const TextStyle(color: Color(0xFF4A6572), fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Color(0xFF4A6572)),
                const SizedBox(width: 4),
                Text(
                  session.formattedTime,
                  style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.chat_bubble_outline,
                  size: 14,
                  color: Color(0xFF4A6572),
                ),
                const SizedBox(width: 4),
                Text(
                  '${session.messages.length} 条消息',
                  style: TextStyle(color: Color(0xFF4A6572), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        trailing: _isMultiSelectMode
            ? null
            : PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.file_download, size: 16),
                        SizedBox(width: 8),
                        Text('导出为 Markdown'),
                      ],
                    ),
                  ),
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
                    case 'export':
                      _exportSingleSession(session);
                      break;
                    case 'delete':
                      _deleteSession(session);
                      break;
                  }
                },
              ),
        onTap: _isMultiSelectMode
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedSessionIds.remove(session.id);
                  } else {
                    _selectedSessionIds.add(session.id);
                  }
                });
              }
            : () => _viewSession(session),
        onLongPress: _isMultiSelectMode
            ? null
            : () {
                setState(() {
                  _isMultiSelectMode = true;
                  _selectedSessionIds.add(session.id);
                });
              },
      ),
    );
  }

  void _deleteSession(ChatSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('删除对话'),
        content: Text('确定要删除 "${session.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final sessions = ref.read(chatSessionsProvider);
              ref.read(chatSessionsProvider.notifier).state = sessions
                  .where((s) => s.id != session.id)
                  .toList();
              final storage = ref.read(storageServiceProvider);
              await storage.deleteSession(session.id);
              // 如果是悬浮窗保存的记录，同时从 Kotlin SharedPreferences 删除
              if (session.id.startsWith('chat_')) {
                try {
                  const channel = MethodChannel('com.yl.aigg/bridge');
                  await channel.invokeMethod('deleteOverlayChat', {'sessionId': session.id});
                } catch (_) {}
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  IconData _getSessionIcon(String title) {
    if (title.contains('💰') || title.contains('金币')) {
      return Icons.monetization_on;
    } else if (title.contains('❤️') || title.contains('血量')) {
      return Icons.favorite;
    } else if (title.contains('⚡') || title.contains('能量')) {
      return Icons.flash_on;
    } else if (title.contains('📜') || title.contains('脚本')) {
      return Icons.code;
    } else if (title.contains('🔍') || title.contains('搜索')) {
      return Icons.search;
    } else if (title.contains('❓') || title.contains('帮助')) {
      return Icons.help;
    } else {
      return Icons.chat;
    }
  }
}

/// 对话会话详情页面
class ChatSessionDetailPage extends StatefulWidget {
  final ChatSession session;

  const ChatSessionDetailPage({super.key, required this.session});

  @override
  State<ChatSessionDetailPage> createState() => _ChatSessionDetailPageState();
}

class _ChatSessionDetailPageState extends State<ChatSessionDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: '导出为 Markdown',
            onPressed: () async {
              try {
                final buffer = StringBuffer();
                buffer.writeln('# ${widget.session.title}');
                buffer.writeln();
                buffer.writeln('> 创建时间: ${widget.session.createdAt.toString().substring(0, 19)}');
                buffer.writeln('> ${widget.session.summary}');
                buffer.writeln();
                buffer.writeln('---');
                buffer.writeln();
                for (final msg in widget.session.messages) {
                  buffer.writeln('## ${msg.isUser ? "👤 用户" : "🤖 GG-AI"}');
                  buffer.writeln();
                  buffer.writeln(msg.content);
                  buffer.writeln();
                  buffer.writeln('---');
                  buffer.writeln();
                }
                buffer.writeln('*导出时间: ${DateTime.now().toString().substring(0, 19)}*');

                final safeTitle = widget.session.title.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '_');
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final fileName = '${safeTitle}_$timestamp.md';

                const channel = MethodChannel('com.yl.aigg/bridge');
                final filePath = await channel.invokeMethod('exportChatToFile', {'fileName': fileName, 'content': buffer.toString()});

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 已导出到: $filePath')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 导出失败: $e')));
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制到剪贴板',
            onPressed: () {
              final exportText =
                  '=== ${widget.session.title} ===\n'
                  '时间: ${widget.session.createdAt.toString().substring(0, 19)}\n\n'
                  '${widget.session.messages.map((msg) {
                    final role = msg.isUser ? '用户' : 'AI助手';
                    return '$role: ${msg.content}';
                  }).join('\n\n')}';

              Clipboard.setData(ClipboardData(text: exportText));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 对话已复制到剪贴板')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 会话信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFFFFFFF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.session.summary, style: const TextStyle(color: Color(0xFF4A6572))),
                const SizedBox(height: 4),
                Text('创建时间: ${widget.session.createdAt.toString().substring(0, 19)}', style: const TextStyle(color: Color(0xFF4A6572), fontSize: 12)),
              ],
            ),
          ),
          // 单 WebView 渲染所有消息
          Expanded(
            child: MarkdownWebView(
              messages: widget.session.messages,
              maxWidth: MediaQuery.of(context).size.width,
            ),
          ),
        ],
      ),
    );
  }
}
