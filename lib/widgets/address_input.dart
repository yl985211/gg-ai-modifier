/// 地址输入组件
/// 支持十六进制和十进制地址输入

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ffi/memory_types.dart';

/// 地址输入组件
class AddressInput extends StatefulWidget {
  /// 标签文本
  final String? label;

  /// 地址值变化回调
  final ValueChanged<int>? onAddressChanged;

  /// 初始地址值
  final int? initialValue;

  /// 是否只读
  final bool readOnly;

  const AddressInput({
    super.key,
    this.label,
    this.onAddressChanged,
    this.initialValue,
    this.readOnly = false,
  });

  @override
  State<AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends State<AddressInput> {
  late TextEditingController _controller;
  bool _isHex = true;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue ?? 0;
    _controller = TextEditingController(
      text: _isHex
          ? '0x${initialValue.toRadixString(16).toUpperCase()}'
          : initialValue.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parseAndNotify() {
    final text = _controller.text.trim();
    int? address;

    if (_isHex) {
      final hex = text.replaceFirst('0x', '').replaceFirst('0X', '');
      address = int.tryParse(hex, radix: 16);
    } else {
      address = int.tryParse(text);
    }

    if (address != null) {
      widget.onAddressChanged?.call(address);
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
            // 十六进制/十进制切换
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleButton('HEX', _isHex, () {
                    setState(() {
                      _isHex = true;
                      _parseAndNotify();
                    });
                  }),
                  _buildToggleButton('DEC', !_isHex, () {
                    setState(() {
                      _isHex = false;
                      _parseAndNotify();
                    });
                  }),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 地址输入框
            Expanded(
              child: TextField(
                controller: _controller,
                readOnly: widget.readOnly,
                decoration: InputDecoration(
                  hintText: _isHex ? '0x00000000' : '0',
                  prefixIcon: const Icon(Icons.memory, size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                keyboardType: TextInputType.text,
                inputFormatters: [
                  if (_isHex)
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX]')),
                ],
                onChanged: (_) => _parseAndNotify(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: widget.readOnly ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3D5AFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Color(0xFF213333) : Color(0xFF4A6572),
          ),
        ),
      ),
    );
  }
}
