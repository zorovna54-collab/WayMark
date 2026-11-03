import 'package:flutter/material.dart';

import '../../services/ai_timeout_preferences.dart';

class AiTimeoutControl extends StatefulWidget {
  const AiTimeoutControl({
    super.key,
    required this.seconds,
    required this.enabled,
    required this.onChanged,
  });
  final int seconds;
  final bool enabled;
  final ValueChanged<int?> onChanged;
  @override
  State<AiTimeoutControl> createState() => _AiTimeoutControlState();
}

class _AiTimeoutControlState extends State<AiTimeoutControl> {
  late bool _custom = !AiTimeoutPreferences.presets.contains(widget.seconds);
  late final _input = TextEditingController(text: '${widget.seconds}');
  bool _invalid = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<int>(
        key: ValueKey('ai-timeout-${_custom ? 0 : widget.seconds}'),
        initialValue: _custom ? 0 : widget.seconds,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Thời gian chờ phản hồi AI',
        ),
        items: [
          for (final n in AiTimeoutPreferences.presets)
            DropdownMenuItem(value: n, child: Text('$n giây')),
          const DropdownMenuItem(value: 0, child: Text('Tùy chỉnh…')),
        ],
        onChanged: !widget.enabled
            ? null
            : (value) {
                setState(() {
                  _custom = value == 0;
                  _invalid = false;
                });
                if (_custom) {
                  _input.text = '${widget.seconds}';
                  widget.onChanged(widget.seconds);
                } else {
                  widget.onChanged(value);
                }
              },
      ),
      if (_custom)
        TextField(
          key: const Key('ai-timeout-custom'),
          controller: _input,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Số giây (10–600)',
            errorText: _invalid ? 'Nhập số nguyên từ 10 đến 600 giây.' : null,
          ),
          onChanged: (text) {
            final value = AiTimeoutPreferences.parse(text);
            setState(() => _invalid = value == null);
            widget.onChanged(value);
          },
        ),
    ],
  );
}
