/// 值编辑器组件
/// 支持多种数据类型的值输入和编辑

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models/memory_result.dart';
import '../core/ffi/memory_types.dart';

/// 值编辑器组件
class ValueEditor extends StatefulWidget {
  /// 数据类型
  final DataType dataType;

  /// 值变化回调
  final ValueChanged<dynamic>? onValueChanged;

  /// 初始值
  final dynamic initialValue;

  /// 标签
  final String? label;

  /// 是否只读
  final bool readOnly;

  const ValueEditor({
    super.key,
    required this.dataType,
    this.onValueChanged,
    this.initialValue,
    this.label,
    this.readOnly = false,
  });

  @override
  State<ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<ValueEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(ValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parseAndNotify() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    dynamic value;
    switch (widget.dataType) {
      case DataType.byte:
      case DataType.word:
      case DataType.dword:
      case DataType.qword:
        value = int.tryParse(text);
        break;
      case DataType.float:
      case DataType.double:
        value = double.tryParse(text);
        break;
      case DataType.string:
        value = text;
        break;
    }

    if (value != null) {
      widget.onValueChanged?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.label!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4A6572)),
            ),
          ),
        Row(
          children: [
            // 数据类型标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3D5AFE).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.dataType.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3D5AFE),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 值输入框
            Expanded(
              child: TextField(
                controller: _controller,
                readOnly: widget.readOnly,
                decoration: InputDecoration(
                  hintText: _getHintText(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                keyboardType: _getKeyboardType(),
                inputFormatters: _getInputFormatters(),
                onChanged: (_) => _parseAndNotify(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getHintText() {
    switch (widget.dataType) {
      case DataType.byte:
        return '0-255';
      case DataType.word:
        return '0-65535';
      case DataType.dword:
        return '0-4294967295';
      case DataType.qword:
        return '0-18446744073709551615';
      case DataType.float:
        return '3.14';
      case DataType.double:
        return '3.14159265358979';
      case DataType.string:
        return '输入字符串';
    }
  }

  TextInputType _getKeyboardType() {
    switch (widget.dataType) {
      case DataType.float:
      case DataType.double:
        return TextInputType.numberWithOptions(decimal: true, signed: true);
      case DataType.string:
        return TextInputType.text;
      default:
        return TextInputType.number;
    }
  }

  List<TextInputFormatter> _getInputFormatters() {
    switch (widget.dataType) {
      case DataType.float:
      case DataType.double:
        return [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))];
      case DataType.string:
        return [];
      default:
        return [FilteringTextInputFormatter.digitsOnly];
    }
  }
}
