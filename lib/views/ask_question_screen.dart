import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/experience_ui.dart';
import '../models/question.dart';
import '../providers/app_providers.dart';
import 'solution_screen.dart';

class AskQuestionScreen extends ConsumerStatefulWidget {
  const AskQuestionScreen({super.key});

  @override
  ConsumerState<AskQuestionScreen> createState() => _AskQuestionScreenState();
}

class _AskQuestionScreenState extends ConsumerState<AskQuestionScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  bool _isSubmitting = false;
  String? _errorText;

  Future<void> _pickAndCrop(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 92,
    );
    if (picked == null) {
      return;
    }

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Crop question',
          toolbarColor: AppColors.primaryBlue,
          toolbarWidgetColor: Colors.white,
          hideBottomControls: false,
        ),
        IOSUiSettings(title: 'Crop question'),
      ],
    );

    if (cropped == null) {
      return;
    }

    setState(() {
      _imageFile = File(cropped.path);
      _errorText = null;
    });
  }

  Future<void> _submitQuestion() async {
    final File? localImage = _imageFile;
    if (localImage == null) {
      setState(() => _errorText = 'Please capture a question image first.');
      return;
    }

    final firebaseService = ref.read(firebaseServiceProvider);
    final user = firebaseService.currentUser;
    if (user == null) {
      setState(() => _errorText = 'Please sign in again.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final String imageUrl = await ref
          .read(supabaseStorageServiceProvider)
          .uploadQuestionImage(imageFile: localImage, userId: user.uid);

      final aiSolution = await ref
          .read(aiTutorServiceProvider)
          .solveQuestion(imageUrl: imageUrl);

      final Question question = Question.newQuestion(
        userId: user.uid,
        imageUrl: imageUrl,
        solutionText: aiSolution.solutionText,
        subject: aiSolution.subject,
        steps: aiSolution.steps,
        finalAnswer: aiSolution.finalAnswer,
      );

      await firebaseService.saveQuestion(question);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SolutionScreen(
            questionId: question.id,
            initialQuestion: question,
          ),
        ),
      );
    } catch (e) {
      setState(() => _errorText = 'Could not solve question: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask a question')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.grey300),
                    color: AppColors.grey100,
                  ),
                  child: _imageFile == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Capture a clear photo of your question.\n'
                              'Crop to include only the required part.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        ),
                ),
              ),
              if (_errorText != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: const TextStyle(color: AppColors.errorRed),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickAndCrop(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Kamera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickAndCrop(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeri'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitQuestion,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isSubmitting ? 'Solving...' : 'Get solution'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
