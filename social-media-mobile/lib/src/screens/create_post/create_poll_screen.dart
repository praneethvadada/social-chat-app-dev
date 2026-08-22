import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../components/visibility_selector.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../state/app_state_manager.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class CreatePollScreen extends ConsumerStatefulWidget {
  const CreatePollScreen({super.key});

  @override
  ConsumerState<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends ConsumerState<CreatePollScreen> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _posting = false;
  PostVisibility _visibility = PostVisibility.PUBLIC;
  bool _isQuiz = false;
  int? _correctOptionIndex;

  static const _maxOptions = 6;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= _maxOptions) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      final removed = _optionCtrls.removeAt(index);
      removed.dispose();
      if (_correctOptionIndex == index) {
        _correctOptionIndex = null;
      } else if (_correctOptionIndex != null && _correctOptionIndex! > index) {
        _correctOptionIndex = _correctOptionIndex! - 1;
      }
    });
  }

  Future<void> _create() async {
    final question = _questionCtrl.text.trim();
    final rawTexts = _optionCtrls.map((c) => c.text.trim()).toList();
    final options = rawTexts.where((t) => t.isNotEmpty).toList();

    if (question.isEmpty) {
      Fluttertoast.showToast(msg: 'Write a question for your poll');
      return;
    }
    if (options.length < 2) {
      Fluttertoast.showToast(msg: 'Add at least 2 options');
      return;
    }
    if (_isQuiz && (_correctOptionIndex == null || rawTexts[_correctOptionIndex!].isEmpty)) {
      Fluttertoast.showToast(msg: 'Pick which option is the correct answer');
      return;
    }

    // Map the correct-answer index from the raw (possibly sparse) option
    // list onto the filtered list actually sent to the backend.
    int? correctOptionIndex;
    if (_isQuiz && _correctOptionIndex != null) {
      correctOptionIndex = rawTexts.sublist(0, _correctOptionIndex!).where((t) => t.isNotEmpty).length;
    }

    setState(() => _posting = true);
    try {
      await ref.read(postProvider.notifier).addPoll(
            question: question,
            options: options,
            visibility: _visibility.name,
            correctOptionIndex: correctOptionIndex,
          );
      Fluttertoast.showToast(msg: 'Poll posted');
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          ref.read(appStateProvider.notifier).closeModal();
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to create poll: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          child: Container(
            color: theme.cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      ref.read(appStateProvider.notifier).closeModal();
                    }
                  },
                ),
                Expanded(
                  child: Center(
                    child: Text('Create Poll',
                        style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _posting ? null : _create,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Post'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Question', style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _questionCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "What's your question?",
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('Options',
                      style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text('Quiz mode', style: TextStyle(color: AppColors.mutedSolid, fontSize: 12.5)),
                Switch(
                  value: _isQuiz,
                  activeColor: primary,
                  onChanged: (v) => setState(() {
                    _isQuiz = v;
                    if (!v) _correctOptionIndex = null;
                  }),
                ),
              ],
            ),
            if (_isQuiz)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Tap the checkmark next to the correct answer.',
                    style: TextStyle(color: AppColors.mutedSolid, fontSize: 12)),
              ),
            for (int i = 0; i < _optionCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    if (_isQuiz)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _correctOptionIndex = i),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _correctOptionIndex == i ? primary : Colors.transparent,
                              border: Border.all(
                                  color: _correctOptionIndex == i ? primary : AppColors.mutedSolid, width: 1.5),
                            ),
                            child: _correctOptionIndex == i
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : null,
                          ),
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Option ${i + 1}',
                          filled: true,
                          fillColor: theme.cardColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 2)
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.mutedSolid),
                        onPressed: () => _removeOption(i),
                      ),
                  ],
                ),
              ),
            if (_optionCtrls.length < _maxOptions)
              TextButton.icon(
                onPressed: _addOption,
                icon: Icon(Icons.add, color: primary),
                label: Text('Add option', style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            VisibilitySelector(
              value: _visibility,
              onChanged: (v) => setState(() => _visibility = v),
            ),
          ],
        ),
      ),
    );
  }
}
