/// 本地存储服务
///
/// 使用 Hive 进行本地数据持久化
/// 支持 Sessions、Messages、Bookmarks 结构化存储

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/llm/llm_config.dart';
import '../core/models/chat_message.dart';
import '../core/models/chat_session.dart';
import '../core/models/script_model.dart';
import '../core/models/memory_result.dart';
import '../core/models/bookmark_model.dart';
import '../core/models/skill_model.dart';

/// 存储服务
class StorageService {
  static const String _llmConfigBox = 'llm_config';
  static const String _chatHistoryBox = 'chat_history';
  static const String _sessionsBox = 'sessions';
  static const String _scriptsBox = 'scripts';
  static const String _favoritesBox = 'favorites';
  static const String _bookmarksBox = 'bookmarks';
  static const String _settingsBox = 'settings';
  static const String _skillsBox = 'skills';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 初始化存储
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();
    await Hive.openBox(_llmConfigBox);
    await Hive.openBox(_chatHistoryBox);
    await Hive.openBox(_sessionsBox);
    await Hive.openBox(_scriptsBox);
    await Hive.openBox(_favoritesBox);
    await Hive.openBox(_bookmarksBox);
    await Hive.openBox(_settingsBox);
    await Hive.openBox(_skillsBox);

    _isInitialized = true;
  }

  // ==================== LLM 配置 ====================

  /// 保存 LLM 配置
  Future<void> saveLlmConfig(LlmConfig config) async {
    final box = Hive.box(_llmConfigBox);
    await box.put('current', jsonEncode(config.toJson()));
  }

  /// 获取 LLM 配置
  LlmConfig? getLlmConfig() {
    final box = Hive.box(_llmConfigBox);
    final json = box.get('current') as String?;
    if (json == null) return null;
    return LlmConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // ==================== 聊天历史 (旧版兼容) ====================

  /// 保存聊天历史
  Future<void> saveChatHistory(List<ChatMessage> messages) async {
    final box = Hive.box(_chatHistoryBox);
    final jsonList = messages.map((m) => m.toJson()).toList();
    await box.put('history', jsonEncode(jsonList));
  }

  /// 获取聊天历史
  List<ChatMessage> getChatHistory() {
    final box = Hive.box(_chatHistoryBox);
    final json = box.get('history') as String?;
    if (json == null) return [];

    final List<dynamic> jsonList = jsonDecode(json) as List<dynamic>;
    return jsonList.map((item) {
      return ChatMessage.fromJson(item as Map<String, dynamic>);
    }).toList();
  }

  /// 清空聊天历史
  Future<void> clearChatHistory() async {
    final box = Hive.box(_chatHistoryBox);
    await box.delete('history');
  }

  // ==================== 会话管理 (Sessions) ====================

  /// 保存会话
  Future<void> saveSession(ChatSession session) async {
    final box = Hive.box(_sessionsBox);
    await box.put(session.id, jsonEncode(session.toJson()));
  }

  /// 获取所有会话（按更新时间倒序）
  List<ChatSession> getAllSessions() {
    final box = Hive.box(_sessionsBox);
    final sessions = box.values.map((item) {
      final json = item as String;
      return ChatSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }).toList();

    // 按更新时间倒序排列
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  /// 获取单个会话
  ChatSession? getSession(String id) {
    final box = Hive.box(_sessionsBox);
    final json = box.get(id) as String?;
    if (json == null) return null;
    return ChatSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 删除会话
  Future<void> deleteSession(String id) async {
    final box = Hive.box(_sessionsBox);
    await box.delete(id);
  }

  /// 清空所有会话
  Future<void> clearAllSessions() async {
    final box = Hive.box(_sessionsBox);
    await box.clear();
  }

  /// 向会话添加消息
  Future<void> addMessageToSession(
    String sessionId,
    ChatMessage message,
  ) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final updatedMessages = [...session.messages, message];
    final updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
    await saveSession(updatedSession);
  }

  /// 获取会话消息（剔除海量地址数据，只保留文本消息）
  List<ChatMessage> getSessionMessages(
    String sessionId, {
    bool excludeAddressData = true,
  }) {
    final session = getSession(sessionId);
    if (session == null) return [];

    if (!excludeAddressData) return session.messages;

    // 过滤掉包含大量地址数据的消息（节省存储空间）
    return session.messages.where((msg) {
      // 保留用户消息和 AI 文本回复
      if (msg.isUser || msg.type == MessageType.text) return true;
      // 保留函数调用信息（但不保留大量结果数据）
      if (msg.type == MessageType.functionCall) return true;
      // 函数结果消息如果太长则截断
      if (msg.type == MessageType.functionResult && msg.content.length > 1000)
        return false;
      return true;
    }).toList();
  }

  // ==================== 脚本管理 ====================

  /// 保存脚本
  Future<void> saveScript(ScriptModel script) async {
    final box = Hive.box(_scriptsBox);
    await box.put(script.id, jsonEncode(script.toJson()));
  }

  /// 获取所有脚本
  List<ScriptModel> getAllScripts() {
    final box = Hive.box(_scriptsBox);
    return box.values.map((item) {
      final json = item as String;
      return ScriptModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }).toList();
  }

  /// 获取脚本
  ScriptModel? getScript(String id) {
    final box = Hive.box(_scriptsBox);
    final json = box.get(id) as String?;
    if (json == null) return null;
    return ScriptModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 删除脚本
  Future<void> deleteScript(String id) async {
    final box = Hive.box(_scriptsBox);
    await box.delete(id);
  }

  // ==================== 收藏地址 ====================

  /// 保存收藏地址
  Future<void> saveFavorite(MemoryResult result) async {
    final box = Hive.box(_favoritesBox);
    await box.put(result.address, jsonEncode(result.toJson()));
  }

  /// 获取所有收藏地址
  List<MemoryResult> getFavorites() {
    final box = Hive.box(_favoritesBox);
    return box.values.map((item) {
      final json = item as String;
      return MemoryResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }).toList();
  }

  /// 删除收藏地址
  Future<void> deleteFavorite(String address) async {
    final box = Hive.box(_favoritesBox);
    await box.delete(address);
  }

  // ==================== 书签管理 (Bookmarks) ====================

  /// 保存书签
  Future<void> saveBookmark(BookmarkModel bookmark) async {
    final box = Hive.box(_bookmarksBox);
    await box.put(bookmark.id, jsonEncode(bookmark.toJson()));
  }

  /// 获取所有书签（按更新时间倒序）
  List<BookmarkModel> getAllBookmarks() {
    final box = Hive.box(_bookmarksBox);
    final bookmarks = box.values.map((item) {
      final json = item as String;
      return BookmarkModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }).toList();

    bookmarks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return bookmarks;
  }

  /// 获取指定游戏的书签
  List<BookmarkModel> getBookmarksByPackage(String packageName) {
    return getAllBookmarks()
        .where((b) => b.packageName == packageName)
        .toList();
  }

  /// 获取单个书签
  BookmarkModel? getBookmark(String id) {
    final box = Hive.box(_bookmarksBox);
    final json = box.get(id) as String?;
    if (json == null) return null;
    return BookmarkModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 删除书签
  Future<void> deleteBookmark(String id) async {
    final box = Hive.box(_bookmarksBox);
    await box.delete(id);
  }

  /// 更新书签值
  Future<void> updateBookmarkValue(String id, dynamic newValue) async {
    final bookmark = getBookmark(id);
    if (bookmark == null) return;

    final updated = bookmark.copyWith(
      currentValue: newValue,
      updatedAt: DateTime.now(),
    );
    await saveBookmark(updated);
  }

  /// 切换书签冻结状态
  Future<void> toggleBookmarkFreeze(String id, dynamic freezeValue) async {
    final bookmark = getBookmark(id);
    if (bookmark == null) return;

    final updated = bookmark.copyWith(
      isFrozen: !bookmark.isFrozen,
      frozenValue: bookmark.isFrozen ? null : freezeValue,
      updatedAt: DateTime.now(),
    );
    await saveBookmark(updated);
  }

  // ==================== 通用设置 ====================

  /// 保存设置
  Future<void> saveSetting(String key, dynamic value) async {
    final box = Hive.box(_settingsBox);
    await box.put(key, value);
  }

  /// 获取设置
  dynamic getSetting(String key, {dynamic defaultValue}) {
    final box = Hive.box(_settingsBox);
    return box.get(key, defaultValue: defaultValue);
  }

  /// 删除设置
  Future<void> deleteSetting(String key) async {
    final box = Hive.box(_settingsBox);
    await box.delete(key);
  }

  // ==================== Skill 管理 ====================

  /// 保存 Skill
  Future<void> saveSkill(SkillModel skill) async {
    final box = Hive.box(_skillsBox);
    await box.put(skill.id, jsonEncode(skill.toJson()));
  }

  /// 获取所有 Skill
  List<SkillModel> getAllSkills() {
    final box = Hive.box(_skillsBox);
    return box.values.map((item) {
      final json = item as String;
      return SkillModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }).toList();
  }

  /// 获取已启用的 Skill 列表
  List<SkillModel> getEnabledSkills() {
    return getAllSkills().where((skill) => skill.isEnabled).toList();
  }

  /// 获取单个 Skill
  SkillModel? getSkill(String id) {
    final box = Hive.box(_skillsBox);
    final json = box.get(id) as String?;
    if (json == null) return null;
    return SkillModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 删除 Skill
  Future<void> deleteSkill(String id) async {
    final box = Hive.box(_skillsBox);
    await box.delete(id);
  }

  /// 切换 Skill 启用状态
  Future<void> toggleSkill(String id) async {
    final skill = getSkill(id);
    if (skill == null) return;
    final updated = skill.copyWith(
      isEnabled: !skill.isEnabled,
      updatedAt: DateTime.now(),
    );
    await saveSkill(updated);
  }

  /// 释放资源
  Future<void> dispose() async {
    await Hive.close();
    _isInitialized = false;
  }
}
