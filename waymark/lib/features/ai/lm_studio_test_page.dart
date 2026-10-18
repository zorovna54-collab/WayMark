import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/lm_studio_service.dart';

enum _ConnectionState { notChecked, checking, connected, empty, failed }

class LmStudioTestPage extends StatefulWidget {
  const LmStudioTestPage({super.key});

  @override
  State<LmStudioTestPage> createState() => _LmStudioTestPageState();
}

class _LmStudioTestPageState extends State<LmStudioTestPage> {
  final _questionController = TextEditingController();
  late final LmStudioService _service;

  _ConnectionState _connectionState = _ConnectionState.notChecked;
  List<String> _models = const [];
  String? _selectedModel;
  String? _connectionError;
  String? _requestError;
  String? _answer;
  bool _isChecking = false;
  bool _isSending = false;

  bool get _isBusy => _isChecking || _isSending;

  @override
  void initState() {
    super.initState();
    _service = LmStudioService();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    if (_isBusy) return;
    setState(() {
      _isChecking = true;
      _connectionState = _ConnectionState.checking;
      _connectionError = null;
    });

    try {
      final models = await _service.getModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _selectedModel = models.contains(_selectedModel)
            ? _selectedModel
            : models.firstOrNull;
        _connectionState = models.isEmpty
            ? _ConnectionState.empty
            : _ConnectionState.connected;
      });
    } on LmStudioException catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionState = _ConnectionState.failed;
        _connectionError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionState = _ConnectionState.failed;
        _connectionError = 'Không thể kiểm tra LM Studio: $error';
      });
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _sendQuestion() async {
    if (_isBusy) return;
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _requestError = 'Hãy nhập câu hỏi trước khi gửi.');
      return;
    }

    setState(() {
      _isSending = true;
      _requestError = null;
      _answer = null;
    });

    try {
      var model = _selectedModel;
      if (model == null) {
        final models = await _service.getModels();
        if (!mounted) return;
        setState(() {
          _models = models;
          _selectedModel = models.firstOrNull;
          _connectionState = models.isEmpty
              ? _ConnectionState.empty
              : _ConnectionState.connected;
        });
        if (models.isEmpty) {
          throw const LmStudioException(
            'LM Studio kết nối được nhưng chưa có model để chat.',
          );
        }
        model = models.first;
      }

      final answer = await _service.ask(model: model, question: question);
      if (!mounted) return;
      setState(() => _answer = answer);
    } on LmStudioException catch (error) {
      if (!mounted) return;
      setState(() => _requestError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _requestError = 'Không thể gửi câu hỏi: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kiểm thử LM Studio AI'),
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.primary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 12),
            _buildModelCard(),
            const SizedBox(height: 12),
            _buildQuestionCard(),
            if (_requestError != null) ...[
              const SizedBox(height: 12),
              _messageCard(
                icon: Icons.error_outline,
                color: Colors.red.shade700,
                message: _requestError!,
              ),
            ],
            if (_isSending) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_answer != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Câu trả lời',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(_answer!),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kết nối LM Studio',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text('Địa chỉ: ${_service.baseUrl}'),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusLabel,
                  style: TextStyle(color: _statusColor),
                ),
              ),
              FilledButton.icon(
                onPressed: _isBusy ? null : _checkConnection,
                icon: _isChecking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Kiểm tra kết nối'),
              ),
            ],
          ),
          if (_connectionError != null) ...[
            const SizedBox(height: 10),
            Text(
              _connectionError!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildModelCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Model đang sử dụng',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_models.isEmpty)
            const Text('Chưa có model. Hãy kiểm tra kết nối LM Studio.')
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedModel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.memory_outlined),
              ),
              items: [
                for (final model in _models)
                  DropdownMenuItem(value: model, child: Text(model)),
              ],
              onChanged: _isBusy
                  ? null
                  : (value) => setState(() => _selectedModel = value),
            ),
        ],
      ),
    ),
  );

  Widget _buildQuestionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Câu hỏi',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _questionController,
            minLines: 3,
            maxLines: 6,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              hintText: 'Nhập câu hỏi để gửi đến model...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isBusy ? null : _sendQuestion,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Gửi câu hỏi'),
          ),
        ],
      ),
    ),
  );

  Widget _messageCard({
    required IconData icon,
    required Color color,
    required String message,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    ),
  );

  IconData get _statusIcon => switch (_connectionState) {
    _ConnectionState.notChecked => Icons.help_outline,
    _ConnectionState.checking => Icons.sync,
    _ConnectionState.connected => Icons.check_circle_outline,
    _ConnectionState.empty => Icons.warning_amber_outlined,
    _ConnectionState.failed => Icons.error_outline,
  };

  Color get _statusColor => switch (_connectionState) {
    _ConnectionState.connected => Colors.green.shade700,
    _ConnectionState.failed => Colors.red.shade700,
    _ConnectionState.empty => Colors.orange.shade800,
    _ => AppColors.textSecondary,
  };

  String get _statusLabel => switch (_connectionState) {
    _ConnectionState.notChecked => 'Chưa kiểm tra kết nối.',
    _ConnectionState.checking => 'Đang kiểm tra...',
    _ConnectionState.connected => 'Đã kết nối với LM Studio.',
    _ConnectionState.empty => 'Kết nối được nhưng danh sách model đang rỗng.',
    _ConnectionState.failed => 'Kết nối thất bại.',
  };
}
