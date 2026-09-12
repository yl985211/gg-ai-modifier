/// LLM API 调用服务
///
/// 支持 OpenAI 兼容 API（包括 Gemini OpenAI 兼容接口）

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_config.dart';
import '../models/chat_message.dart';
import 'function_handler.dart';
import 'prompt_builder.dart';

/// LLM 服务类
class LlmService {
  LlmConfig _config;
  final FunctionHandler _functionHandler;
  final PromptBuilder _promptBuilder;

  http.Client? _httpClient;
  bool _isStreaming = false;

  LlmService({
    required LlmConfig config,
    required FunctionHandler functionHandler,
    required PromptBuilder promptBuilder,
  })  : _config = config,
        _functionHandler = functionHandler,
        _promptBuilder = promptBuilder {
    promptBuilder.setModelName(config.model);
  }

  /// 当前配置
  LlmConfig get config => _config;

  /// 是否正在流式响应
  bool get isStreaming => _isStreaming;

  /// 更新配置
  void updateConfig(LlmConfig newConfig) {
    _config = newConfig;
    _promptBuilder.setModelName(newConfig.model);
  }

  /// 获取实际请求的 URL
  String _getEndpoint() {
    // Gemini 使用 OpenAI 兼容接口: /v1beta/openai/chat/completions
    final base = _config.effectiveBaseUrl.trimRight('/');
    return '$base/chat/completions';
  }

  /// 发送聊天消息 (非流式)
  Future<ChatMessage> sendMessage(
    String userMessage, {
    List<ChatMessage> history = const [],
  }) async {
    if (!_config.isConfigured) {
      return ChatMessage.assistant('⚠️ 请先在设置中配置 LLM API');
    }

    try {
      final messages = _promptBuilder.buildMessages(
        userMessage: userMessage,
        history: history,
      );

      final response = await _makeRequest(messages, stream: false);

      if (response == null) {
        return ChatMessage.assistant('❌ 请求失败，请检查网络和 API 配置');
      }

      final choice = response['choices']?[0];
      if (choice == null) {
        return ChatMessage.assistant('❌ 响应格式错误');
      }

      final message = choice['message'];
      final content = message['content'] as String? ?? '';

      // 检查是否有函数调用
      if (message['tool_calls'] != null) {
        final toolCalls = message['tool_calls'] as List;
        if (toolCalls.isNotEmpty) {
          final toolCall = toolCalls[0];
          final funcName = toolCall['function']['name'] as String;
          final funcArgs = jsonDecode(toolCall['function']['arguments'] as String);

          // 执行函数调用
          final result = await _functionHandler.executeFunction(funcName, funcArgs);

          // 将结果返回给 LLM 生成总结
          final summary = await _sendFunctionResult(
            funcName: funcName,
            arguments: funcArgs,
            result: result,
            history: history,
            toolCallId: toolCall['id'] as String?,
          );

          return summary;
        }
      }

      return ChatMessage.assistant(content);
    } catch (e) {
      return ChatMessage.assistant('❌ 发生错误: $e');
    }
  }

  /// 发送聊天消息 (流式)
  Stream<String> sendMessageStream(
    String userMessage, {
    List<ChatMessage> history = const [],
  }) async* {
    if (!_config.isConfigured) {
      yield '⚠️ 请先在设置中配置 LLM API';
      return;
    }

    _isStreaming = true;

    try {
      final messages = _promptBuilder.buildMessages(
        userMessage: userMessage,
        history: history,
      );

      final endpoint = _getEndpoint();
      final request = http.Request('POST', Uri.parse(endpoint));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer ${_config.apiKey}';
      request.body = jsonEncode({
        'model': _config.model,
        'messages': messages,
        'temperature': _config.temperature,
        'max_tokens': _config.maxTokens,
        'stream': true,
        'tools': _functionHandler.getToolDefinitions(),
      });

      final streamedResponse = await _getClient().send(request);

      if (streamedResponse.statusCode != 200) {
        yield '❌ API 请求失败 (${streamedResponse.statusCode})';
        _isStreaming = false;
        return;
      }

      String buffer = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;

        final lines = buffer.split('\n');
        buffer = lines.last;

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          final data = line.substring(6);
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data);
            final delta = json['choices']?[0]?['delta'];

            if (delta != null) {
              if (delta['tool_calls'] != null) {
                final toolCalls = delta['tool_calls'] as List;
                if (toolCalls.isNotEmpty) {
                  final funcName = toolCalls[0]['function']?['name'] as String?;
                  if (funcName != null) {
                    yield '\n\n🔧 正在执行: $funcName...\n';
                  }
                }
              }

              final content = delta['content'] as String?;
              if (content != null) {
                yield content;
              }
            }
          } catch (e) {
            // 忽略解析错误
          }
        }
      }
    } catch (e) {
      yield '\n\n❌ 流式响应错误: $e';
    } finally {
      _isStreaming = false;
    }
  }

  /// 发送函数执行结果给 LLM
  Future<ChatMessage> _sendFunctionResult({
    required String funcName,
    required Map<String, dynamic> arguments,
    required dynamic result,
    required List<ChatMessage> history,
    String? toolCallId,
  }) async {
    try {
      final messages = _promptBuilder.buildFunctionResultMessages(
        funcName: funcName,
        arguments: arguments,
        result: result,
        history: history,
      );

      // 添加工具调用结果消息
      if (toolCallId != null) {
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': result.toString(),
        });
      }

      final response = await _makeRequest(messages, stream: false);

      if (response == null) {
        return ChatMessage.assistant('函数执行完成，但无法获取 AI 总结');
      }

      final content =
          response['choices']?[0]?['message']?['content'] as String? ?? '';
      return ChatMessage.assistant(content);
    } catch (e) {
      return ChatMessage.assistant('函数执行完成: $result');
    }
  }

  /// 发送 API 请求
  Future<Map<String, dynamic>?> _makeRequest(
    List<Map<String, dynamic>> messages, {
    bool stream = false,
  }) async {
    try {
      final endpoint = _getEndpoint();
      final response = await _getClient().post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config.apiKey}',
        },
        body: jsonEncode({
          'model': _config.model,
          'messages': messages,
          'temperature': _config.temperature,
          'max_tokens': _config.maxTokens,
          'stream': stream,
          'tools': _functionHandler.getToolDefinitions(),
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        print('API 请求失败: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('API 请求异常: $e');
      return null;
    }
  }

  /// 获取 HTTP 客户端
  http.Client _getClient() {
    _httpClient ??= http.Client();
    return _httpClient!;
  }

  /// 释放资源
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
    _isStreaming = false;
  }
}
