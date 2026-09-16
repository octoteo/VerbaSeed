import 'package:flutter/material.dart';

class SentenceTypingPage extends StatefulWidget {
  const SentenceTypingPage({super.key});

  @override
  State<SentenceTypingPage> createState() => _SentenceTypingPageState();
}

class _SentenceTypingPageState extends State<SentenceTypingPage> {
  static const _words = ['on', 'the', 'street'];
  static const _hints = ['在', '这 / 该', '街道'];

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  List<bool?> _results = List<bool?>.filled(_words.length, null);

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_words.length, (_) => TextEditingController());
    _focusNodes = List.generate(_words.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _check() {
    final results = List<bool>.generate(
      _words.length,
      (index) => _controllers[index].text.trim().toLowerCase() == _words[index],
    );
    setState(() => _results = results);

    final firstWrong = results.indexWhere((result) => !result);
    if (firstWrong >= 0) {
      _focusNodes[firstWrong].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _reset() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() => _results = List<bool?>.filled(_words.length, null));
    _focusNodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final complete = _results.every((result) => result == true);

    return Scaffold(
      appBar: AppBar(title: const Text('句子输入')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('在街上', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 10),
                  Text('根据中文输入英文短语', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 600;
                      final children = List.generate(_words.length, _buildWordField);
                      return compact
                          ? Column(children: children)
                          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: children.map((child) => Expanded(child: child)).toList());
                    },
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: complete
                        ? Card(
                            key: const ValueKey('success'),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 12),
                                  const Expanded(child: Text('很好！“on the street” 已完成。下一步会记录表现并安排复习。')),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh), label: const Text('重来')),
                      const SizedBox(width: 12),
                      FilledButton.icon(onPressed: _check, icon: const Icon(Icons.check), label: const Text('检查')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordField(int index) {
    final result = _results[index];
    final scheme = Theme.of(context).colorScheme;
    final borderColor = result == null
        ? scheme.outlineVariant
        : result
            ? scheme.primary
            : scheme.error;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: index == _words.length - 1 ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) {
              if (index == _words.length - 1) {
                _check();
              } else {
                _focusNodes[index + 1].requestFocus();
              }
            },
            onChanged: (_) {
              if (_results[index] != null) {
                setState(() => _results[index] = null);
              }
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: borderColor, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: result == false ? scheme.error : scheme.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(_hints[index], style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
