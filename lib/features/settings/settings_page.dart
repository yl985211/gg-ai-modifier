/// 设置页面

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart' as genai;
import '../../core/llm/llm_config.dart';
import '../../core/llm/prompt_builder.dart';
import '../../main.dart';

/// LLM 配置 Provider
final llmConfigProvider = StateProvider<LlmConfig>((ref) {
  // 从存储加载配置
  final storage = ref.read(storageServiceProvider);
  final saved = storage.getLlmConfig();
  return saved ??
      const LlmConfig(baseUrl: '', apiKey: '', model: 'deepseek-chat');
});

/// 设置页面
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _temperatureController;
  late TextEditingController _maxTokensController;

  String _selectedPreset = 'custom';
  bool _isTesting = false;
  String? _testResult;
  AiReadDepth _selectedReadDepth = AiReadDepth.sample50;

  /// 自定义预设列表（从存储加载）
  final Map<String, LlmConfig> _customPresets = {};

  @override
  void initState() {
    super.initState();
    final config = ref.read(llmConfigProvider);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelController = TextEditingController(text: config.model);
    _temperatureController = TextEditingController(
      text: config.temperature.toString(),
    );
    _maxTokensController = TextEditingController(
      text: config.maxTokens.toString(),
    );

    // 加载存储服务
    final storage = ref.read(storageServiceProvider);

    // 加载自定义预设
    _loadCustomPresets(storage);

    // 恢复保存的预设名称
    final savedPreset = storage.getSetting('llm_preset') as String?;
    if (savedPreset != null) {
      _selectedPreset = savedPreset;
    } else {
      _selectedPreset = _detectPreset(config);
    }

    // 加载悬浮窗自动开启设置
    _autoStartOverlay =
        storage.getSetting('auto_start_overlay', defaultValue: false) as bool;
    if (_autoStartOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toggleOverlay(true);
      });
    }
    // 加载 AI 读取深度设置
    final depthIndex =
        storage.getSetting('ai_read_depth', defaultValue: 2) as int;
    _selectedReadDepth =
        AiReadDepth.values[depthIndex.clamp(0, AiReadDepth.values.length - 1)];
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _temperatureController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  /// 加载自定义预设
  void _loadCustomPresets(dynamic storage) {
    try {
      final json = storage.getSetting('custom_presets') as String?;
      if (json != null) {
        final Map<String, dynamic> decoded = Map<String, dynamic>.from(
          const JsonDecoder().convert(json) as Map,
        );
        for (final entry in decoded.entries) {
          _customPresets[entry.key] = LlmConfig.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    } catch (_) {}
  }

  /// 保存自定义预设
  void _saveCustomPresets() {
    final storage = ref.read(storageServiceProvider);
    final json = _customPresets.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    storage.saveSetting('custom_presets', const JsonEncoder().convert(json));
  }

  /// 根据当前配置自动匹配预设
  String _detectPreset(LlmConfig config) {
    // 检查内置预设
    for (final entry in LlmConfig.presets.entries) {
      if (entry.value.baseUrl == config.baseUrl &&
          entry.value.model == config.model) {
        return entry.key;
      }
    }
    // 检查自定义预设
    for (final entry in _customPresets.entries) {
      if (entry.value.baseUrl == config.baseUrl &&
          entry.value.model == config.model) {
        return entry.key;
      }
    }
    return 'custom';
  }

  /// 获取所有预设（内置 + 自定义）
  Map<String, LlmConfig> get _allPresets => {
    ...LlmConfig.presets,
    ..._customPresets,
  };

  void _applyPreset(String presetName) {
    if (presetName == 'custom') {
      _showAddCustomPresetDialog();
      return;
    }
    final preset = _allPresets[presetName];
    if (preset != null) {
      // 保存当前预设的 apiKey
      _saveCurrentPresetApiKey();
      setState(() {
        _selectedPreset = presetName;
        _baseUrlController.text = preset.baseUrl;
        _modelController.text = preset.model;
        // 恢复该预设保存的 apiKey
        final storage = ref.read(storageServiceProvider);
        final savedKey =
            storage.getSetting('preset_key_$presetName') as String?;
        _apiKeyController.text = savedKey ?? preset.apiKey;
      });
    }
  }

  /// 保存当前预设的 apiKey
  void _saveCurrentPresetApiKey() {
    final apiKey = _apiKeyController.text.trim();
    if (_selectedPreset != 'custom' && apiKey.isNotEmpty) {
      final storage = ref.read(storageServiceProvider);
      storage.saveSetting('preset_key_$_selectedPreset', apiKey);
    }
  }

  /// 显示添加自定义预设对话框
  void _showAddCustomPresetDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final keyController = TextEditingController();
    final modelController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('添加自定义模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '显示名称',
                  hintText: '如：我的API',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://api.example.com/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: 'gpt-4o',
                ),
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
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final key = keyController.text.trim();
              final model = modelController.text.trim();

              if (name.isEmpty || url.isEmpty || model.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请填写完整信息')));
                return;
              }

              final keyId = 'custom_$name';
              final config = LlmConfig(baseUrl: url, apiKey: key, model: model);

              setState(() {
                _customPresets[keyId] = config;
                _selectedPreset = keyId;
                _baseUrlController.text = url;
                _apiKeyController.text = key;
                _modelController.text = model;
              });

              _saveCustomPresets();
              _saveCurrentPresetApiKey();
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示删除自定义预设对话框
  void _showDeleteCustomPresetsDialog() {
    // 如果没有自定义预设，显示提示
    if (_customPresets.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          title: const Text('删除自定义模型'),
          content: const Text('暂无自定义模型可删除。\n\n请点击"+ 添加自定义"按钮添加自定义模型。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final selectedToDelete = <String>{};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          title: const Text('删除自定义模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _customPresets.entries.map((entry) {
                final displayName = entry.key.replaceFirst('custom_', '');
                return CheckboxListTile(
                  title: Text(displayName),
                  subtitle: Text(
                    entry.value.model,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
                  ),
                  value: selectedToDelete.contains(entry.key),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedToDelete.add(entry.key);
                      } else {
                        selectedToDelete.remove(entry.key);
                      }
                    });
                  },
                  activeColor: const Color(0xFFE53935),
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
              onPressed: selectedToDelete.isEmpty
                  ? null
                  : () {
                      final deletedCurrentPreset = selectedToDelete.contains(_selectedPreset);
                      setState(() {
                        for (final key in selectedToDelete) {
                          _customPresets.remove(key);
                        }
                      });
                      _saveCustomPresets();
                      // 如果删除的是当前选中的预设，自动切换到 DeepSeek 并保存
                      if (deletedCurrentPreset) {
                        _applyPreset('deepseek');
                        _saveConfig();
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ 已删除 ${selectedToDelete.length} 个自定义模型'),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
              ),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveConfig() {
    final config = LlmConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      temperature: double.tryParse(_temperatureController.text) ?? 0.7,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 4096,
    );

    ref.read(llmConfigProvider.notifier).state = config;

    // 如果当前选择的是自定义预设，同步更新 _customPresets 中的配置
    if (_selectedPreset.startsWith('custom_') &&
        _customPresets.containsKey(_selectedPreset)) {
      _customPresets[_selectedPreset] = config;
      _saveCustomPresets();
    }

    // 持久化保存到 Hive
    final storage = ref.read(storageServiceProvider);
    storage.saveLlmConfig(config);
    // 保存当前预设名称
    storage.saveSetting('llm_preset', _selectedPreset);

    // 同时保存到 SharedPreferences（供悬浮窗读取）
    _saveConfigToSharedPreferences(config);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ 配置已保存')));
  }

  /// 保存 LLM 配置到 SharedPreferences（供悬浮窗 Kotlin 代码读取）
  Future<void> _saveConfigToSharedPreferences(LlmConfig config) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      await channel.invokeMethod('saveLlmConfig', {
        'baseUrl': config.baseUrl,
        'apiKey': config.apiKey,
        'model': config.model,
        'temperature': config.temperature,
        'maxTokens': config.maxTokens,
      });
    } catch (e) {
      // 忽略错误
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      setState(() {
        _isTesting = false;
        _testResult = '❌ 请先填写 API 地址和密钥';
      });
      return;
    }

    // 检测是否是 Gemini API
    final isGemini = baseUrl.contains('generativelanguage.googleapis.com');

    try {
      if (isGemini) {
        // Gemini 使用官方 SDK 测试
        await _testGeminiConnection(apiKey, model);
      } else {
        // OpenAI 兼容 API
        await _testOpenAIConnection(baseUrl, apiKey, model);
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('TimeoutException')) {
          _testResult = '❌ 连接超时，请检查网络';
        } else if (e.toString().contains('SocketException')) {
          _testResult = '❌ 网络不可用，请检查网络连接\n\n如果使用了 VPN，请确保 VPN 已开启';
        } else {
          _testResult = '❌ 连接失败: $e';
        }
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// 测试 Gemini API 连接（使用 OpenAI 兼容接口）
  Future<void> _testGeminiConnection(String apiKey, String model) async {
    try {
      // 使用 OpenAI 兼容接口: /v1beta/openai/chat/completions
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': 'Hi'},
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['choices'] != null) {
          setState(() {
            _testResult = '✅ Gemini 连接成功！模型: $model';
          });
        } else {
          setState(() {
            _testResult = '⚠️ Gemini 响应格式异常';
          });
        }
      } else if (response.statusCode == 404) {
        setState(() {
          _testResult = '❌ 404 错误\n\nURL: ${uri.toString()}\n\n响应: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}';
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          _testResult = '❌ API Key 无效 (${response.statusCode})';
        });
      } else {
        setState(() {
          _testResult = '❌ 请求失败 (${response.statusCode}): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}';
        });
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('TimeoutException')) {
          _testResult = '❌ 连接超时，请检查网络';
        } else if (e.toString().contains('SocketException')) {
          _testResult = '❌ 网络不可用\n\n如果使用了 VPN，请确保 VPN 已开启';
        } else {
          _testResult = '❌ 连接失败: $e';
        }
      });
    }
  }

  /// 测试 OpenAI 兼容 API 连接
  Future<void> _testOpenAIConnection(String baseUrl, String apiKey, String model) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': 'Hi'},
            ],
            'max_tokens': 5,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['choices'] != null) {
        setState(() {
          _testResult = '✅ 连接成功！模型: $model';
        });
      } else {
        setState(() {
          _testResult = '⚠️ 响应格式异常: ${response.body.substring(0, 100)}';
        });
      }
    } else if (response.statusCode == 401) {
      setState(() {
        _testResult = '❌ API Key 无效 (401)';
      });
    } else if (response.statusCode == 404) {
      setState(() {
        _testResult = '❌ 模型不存在或 API 地址错误 (404)';
      });
    } else {
      setState(() {
        _testResult =
            '❌ 请求失败 (${response.statusCode}): ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF3D5AFE)),
            SizedBox(width: 8),
            Text('设置'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // LLM API 配置
          _buildSectionTitle('🤖 LLM API 配置'),
          const SizedBox(height: 12),

          // 预设选择
          _buildPresetSelector(),
          const SizedBox(height: 16),

          // API 地址
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.deepseek.com',
              prefixIcon: Icon(Icons.link, size: 16),
            ),
          ),
          const SizedBox(height: 12),

          // API Key
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              prefixIcon: Icon(Icons.key, size: 16),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),

          // 模型名称
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: '模型名称',
              hintText: 'deepseek-chat',
              prefixIcon: Icon(Icons.smart_toy, size: 16),
            ),
          ),
          const SizedBox(height: 12),

          // 温度和最大 Token
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _temperatureController,
                  decoration: const InputDecoration(
                    labelText: '温度',
                    hintText: '0.7',
                    prefixIcon: Icon(Icons.thermostat, size: 16),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxTokensController,
                  decoration: const InputDecoration(
                    labelText: '最大 Token',
                    hintText: '4096',
                    prefixIcon: Icon(Icons.token, size: 16),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 保存按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: const Icon(Icons.save),
              label: const Text('保存配置'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 连接测试
          _buildSectionTitle('🔗 连接测试'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: Text(_isTesting ? '测试中...' : '测试连接'),
            ),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅')
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult!.startsWith('✅')
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('✅')
                      ? Colors.green
                      : Colors.red,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // AI 读取深度
          _buildSectionTitle('📊 AI 读取深度 (Token 优化)'),
          const SizedBox(height: 12),
          _buildReadDepthCard(),
          const SizedBox(height: 24),

          // 悬浮窗
          _buildSectionTitle('🎮 悬浮窗'),
          const SizedBox(height: 12),
          _buildOverlayCard(),
          const SizedBox(height: 24),

          // Root 权限
          _buildSectionTitle('🔐 Root 权限'),
          const SizedBox(height: 12),
          _buildRootStatusCard(),
          const SizedBox(height: 24),

          // 关于
          _buildSectionTitle('ℹ️ 关于'),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.info_outline,
            title: 'GG-AI Modifier',
            subtitle: '版本 2.0.0 | AI 驱动的游戏内存修改器',
          ),
          const SizedBox(height: 12),
          // GitHub 开源地址
          Card(
            child: ListTile(
              leading: const Icon(Icons.code, color: Color(0xFF3D5AFE)),
              title: const Text('GitHub 开源地址'),
              subtitle: const Text(
                'https://github.com/yl985211/gg-ai-modifier',
                style: TextStyle(fontSize: 12, color: Color(0xFF3D5AFE)),
              ),
              trailing: const Icon(Icons.open_in_new, color: Color(0xFF4A6572)),
              onTap: () async {
                const url = 'https://github.com/yl985211/gg-ai-modifier';
                try {
                  const channel = MethodChannel('com.yl.aigg/bridge');
                  await channel.invokeMethod('openUrl', {'url': url});
                } catch (_) {}
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠️ 本工具仅供学习研究和个人单机游戏使用，禁止用于在线竞技游戏。',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildPresetSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择 API 提供商',
            style: TextStyle(fontSize: 13, color: Color(0xFF4A6572)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...LlmConfig.presets.entries.map((entry) {
                final isSelected = _selectedPreset == entry.key;
                final labels = {
                  'deepseek': 'DeepSeek',
                  'deepseek-reasoner': 'DeepSeek R1',
                  'xiaomi-mimo': '小米 MiMo',
                  'openai': 'OpenAI',
                  'gemini': 'Gemini',
                };
                return ChoiceChip(
                  label: Text(labels[entry.key] ?? entry.key),
                  selected: isSelected,
                  onSelected: (_) => _applyPreset(entry.key),
                  selectedColor: const Color(0xFF3D5AFE),
                );
              }),
              ..._customPresets.entries.map((entry) {
                final isSelected = _selectedPreset == entry.key;
                final displayName = entry.key.replaceFirst('custom_', '');
                return ChoiceChip(
                  label: Text(displayName),
                  selected: isSelected,
                  onSelected: (_) => _applyPreset(entry.key),
                  selectedColor: const Color(0xFF536DFE),
                );
              }),
              ActionChip(
                label: const Text('+ 添加自定义'),
                onPressed: () => _showAddCustomPresetDialog(),
                backgroundColor: const Color(0xFFE8EAF6),
                labelStyle: const TextStyle(color: Color(0xFF4A6572)),
              ),
              ActionChip(
                label: const Text('删除自定义'),
                onPressed: () => _showDeleteCustomPresetsDialog(),
                backgroundColor: const Color(0xFFFFEBEE),
                labelStyle: const TextStyle(color: Color(0xFFE53935)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rootStatus = '未检测';
  bool _isCheckingRoot = false;

  Future<void> _checkRootAccess() async {
    setState(() {
      _isCheckingRoot = true;
      _rootStatus = '检测中...';
    });

    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      final result = await channel.invokeMethod('checkRootAccess');
      setState(() {
        _rootStatus = result == true ? '已获取 Root 权限 ✅' : '未获取 Root 权限 ❌';
      });
    } catch (e) {
      setState(() {
        _rootStatus = '检测失败: $e';
      });
    } finally {
      setState(() {
        _isCheckingRoot = false;
      });
    }
  }

  Widget _buildRootStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _rootStatus.contains('✅')
                      ? Icons.check_circle
                      : Icons.security,
                  color: _rootStatus.contains('✅')
                      ? Colors.green
                      : const Color(0xFF3D5AFE),
                ),
                const SizedBox(width: 8),
                Text(
                  'Root 状态: $_rootStatus',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '需要 Root 权限才能读写其他进程内存。\n点击下方按钮会触发 Magisk 授权弹窗。',
              style: TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCheckingRoot ? null : _checkRootAccess,
                icon: _isCheckingRoot
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isCheckingRoot ? '检测中...' : '检测 Root 权限'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _overlayEnabled = false;
  bool _autoStartOverlay = false;

  Future<void> _toggleOverlay(bool enable) async {
    try {
      const channel = MethodChannel('com.yl.aigg/bridge');
      if (enable) {
        final started = await channel.invokeMethod('startOverlay');
        setState(() {
          _overlayEnabled = started == true;
        });
        if (started != true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请授予悬浮窗权限')));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('✅ 悬浮窗已开启')));
        }
      } else {
        await channel.invokeMethod('stopOverlay');
        setState(() {
          _overlayEnabled = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('悬浮窗已关闭')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  void _toggleAutoStart(bool value) {
    setState(() {
      _autoStartOverlay = value;
    });
    final storage = ref.read(storageServiceProvider);
    storage.saveSetting('auto_start_overlay', value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '✅ 启动时自动开启悬浮窗' : '已关闭自动开启悬浮窗')),
    );
  }

  Widget _buildOverlayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bubble_chart, color: Color(0xFF3D5AFE)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '游戏内悬浮窗',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _overlayEnabled,
                  onChanged: _toggleOverlay,
                  activeColor: const Color(0xFF3D5AFE),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '开启后会在屏幕上显示一个悬浮球，点击可快速打开 AI 对话、内存搜索等功能，无需切换窗口。',
              style: TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.autorenew, size: 16, color: Color(0xFF4A6572)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('启动时自动开启悬浮窗', style: TextStyle(fontSize: 13)),
                ),
                Switch(
                  value: _autoStartOverlay,
                  onChanged: _toggleAutoStart,
                  activeColor: const Color(0xFF3D5AFE),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadDepthCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.data_usage, color: Color(0xFF3D5AFE)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 读取深度',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '限制发送给 AI 的搜索结果数量，节省 Token 并防止上下文溢出。'
              '当结果过多时，仅发送前 N 条样本和统计数据。',
              style: TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AiReadDepth.values.map((depth) {
                final isSelected = _selectedReadDepth == depth;
                return ChoiceChip(
                  label: Text(depth.label),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedReadDepth = depth;
                    });
                    final storage = ref.read(storageServiceProvider);
                    storage.saveSetting('ai_read_depth', depth.index);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ AI 读取深度已设为: ${depth.label}')),
                    );
                  },
                  selectedColor: const Color(0xFF3D5AFE),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF3D5AFE)),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: trailing,
      ),
    );
  }
}
