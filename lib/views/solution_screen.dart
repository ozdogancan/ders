import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/experience_ui.dart';
import '../models/question.dart';
import '../providers/app_providers.dart';
import '../widgets/math_text_block.dart';

class SolutionScreen extends ConsumerStatefulWidget {
  const SolutionScreen({
    super.key,
    required this.questionId,
    this.initialQuestion,
  });

  final String questionId;
  final Question? initialQuestion;

  @override
  ConsumerState<SolutionScreen> createState() => _SolutionScreenState();
}

class _SolutionScreenState extends ConsumerState<SolutionScreen> {
  bool? _helpfulChoice;
  bool _sendingFeedback = false;

  Future<void> _sendFeedback(bool helpful) async {
    setState(() {
      _sendingFeedback = true;
      _helpfulChoice = helpful;
    });
    try {
      await ref
          .read(firebaseServiceProvider)
          .setQuestionFeedback(questionId: widget.questionId, helpful: helpful);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit feedback: $e')));
    } finally {
      if (mounted) {
        setState(() => _sendingFeedback = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questionAsync = ref.watch(questionProvider(widget.questionId));
    final Question? question = questionAsync.value ?? widget.initialQuestion;

    if (question == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Solution')),
        body: questionAsync.when(
          data: (_) => const Center(child: Text('Question not found.')),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
        ),
      );
    }

    final bool? selectedHelpful = _helpfulChoice ?? question.helpful;

    return Scaffold(
      appBar: AppBar(title: const Text('Solution')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  question.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return const ColoredBox(
                      color: AppColors.grey100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.grey100,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(question.subject),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Step-by-step solution',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ..._buildStepCards(context, question.steps),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFEFF7FF),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Final Answer',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MathTextBlock(text: question.finalAnswer),
                  ],
                ),
              ),
            ),
            if (question.solutionText.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    question.solutionText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Did this help?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Yes'),
                  selected: selectedHelpful == true,
                  onSelected: _sendingFeedback
                      ? null
                      : (_) => _sendFeedback(true),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('No'),
                  selected: selectedHelpful == false,
                  onSelected: _sendingFeedback
                      ? null
                      : (_) => _sendFeedback(false),
                ),
                if (_sendingFeedback) ...<Widget>[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStepCards(BuildContext context, List<String> steps) {
    if (steps.isEmpty) {
      return <Widget>[
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('No detailed steps were returned.'),
          ),
        ),
      ];
    }

    return List<Widget>.generate(steps.length, (index) {
      final step = steps[index];
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Step ${index + 1}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              MathTextBlock(text: step),
            ],
          ),
        ),
      );
    });
  }
}
