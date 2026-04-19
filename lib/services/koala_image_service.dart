import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';

/// Generates interior design images using Gemini image generation via Koala API proxy
/// Free tier: 500 images/day
class KoalaImageService {
  KoalaImageService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Safe substring for log lines — avoids RangeError when body < n chars.
  String _truncForLog(String s, [int n = 200]) =>
      s.length > n ? s.substring(0, n) : s;

  /// Proxy URL for image generation
  Uri get _proxyUri => Uri.parse('${Env.koalaApiUrl}/api/image');

  /// Generate a room redesign image based on style + room type
  Future<Uint8List?> generateRoomDesign({
    required String roomType,
    required String style,
    String? colorPalette,
    String? additionalDetails,
  }) async {
    final prompt = _buildPrompt(
      roomType: roomType,
      style: style,
      colorPalette: colorPalette,
      additionalDetails: additionalDetails,
    );

    return _generateImage(prompt);
  }

  /// Generate a mood board image
  Future<Uint8List?> generateMoodBoard({
    required String style,
    required String roomType,
  }) async {
    final prompt = '''
Create a professional interior design mood board for a $roomType in $style style.
The mood board should include: color swatches, fabric textures, furniture pieces, 
lighting fixtures, and decorative accessories. Arrange them in an elegant collage 
layout on a white background. Professional, clean, magazine-quality layout.
''';

    return _generateImage(prompt);
  }

  /// Generate a "before → after" visualization
  Future<Uint8List?> generateAfterImage({
    required Uint8List beforePhoto,
    required String style,
    required String changes,
  }) async {
    final payload = {
      'contents': [
        {
          'parts': [
            {
              'text': '''
Redesign this room in $style style. Apply these changes: $changes
Keep the same room layout and dimensions but transform the aesthetic.
Make it photorealistic, professional interior photography quality.
'''
            },
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(beforePhoto),
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    };

    try {
      final response = await _client.post(
        _proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        debugPrint('Image gen error: ${response.statusCode} ${_truncForLog(response.body)}');
        return null;
      }

      return _extractImage(response.body);
    } catch (e) {
      debugPrint('Image generation failed: $e');
      return null;
    }
  }

  /// Core image generation call (via proxy)
  Future<Uint8List?> _generateImage(String prompt) async {
    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    };

    try {
      debugPrint('KoalaImage: Generating image via proxy...');
      final response = await _client.post(
        _proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        debugPrint('KoalaImage error: ${response.statusCode}');
        return null;
      }

      return _extractImage(response.body);
    } catch (e) {
      debugPrint('KoalaImage failed: $e');
      return null;
    }
  }

  /// Extract image bytes from Gemini response
  Uint8List? _extractImage(String rawBody) {
    try {
      final data = jsonDecode(rawBody) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;

      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
      final parts = content['parts'] as List<dynamic>? ?? [];

      for (final part in parts) {
        final p = part as Map<String, dynamic>;
        if (p.containsKey('inline_data')) {
          final inlineData = p['inline_data'] as Map<String, dynamic>;
          final b64 = inlineData['data'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            return base64Decode(b64);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('KoalaImage extract error: $e');
      return null;
    }
  }

  /// Build a detailed interior design prompt
  String _buildPrompt({
    required String roomType,
    required String style,
    String? colorPalette,
    String? additionalDetails,
  }) {
    final roomTr = {
      'salon': 'living room',
      'mutfak': 'kitchen',
      'yatak_odasi': 'bedroom',
      'banyo': 'bathroom',
      'balkon': 'balcony',
      'cocuk_odasi': 'kids room',
      'ofis': 'home office',
      'antre': 'entryway',
    };

    final styleTr = {
      'japandi': 'Japandi (Japanese minimalism meets Scandinavian warmth)',
      'scandinavian': 'Scandinavian (bright, minimal, functional, light wood)',
      'modern': 'Modern minimalist (clean lines, neutral palette, sleek)',
      'bohemian': 'Bohemian (layered textures, warm colors, eclectic)',
      'industrial': 'Industrial (exposed brick, metal, raw materials)',
      'rustic': 'Rustic (natural wood, stone, warm earth tones)',
      'art_deco': 'Art Deco (geometric patterns, gold accents, luxurious)',
      'coastal': 'Coastal (white, blue, natural textures, airy)',
    };

    final room = roomTr[roomType] ?? roomType;
    final styleDesc = styleTr[style] ?? style;

    var prompt = '''
Professional interior design photograph of a beautiful $room in $styleDesc style.
High-end interior photography, natural lighting, photorealistic.
The space should feel inviting, well-designed, and magazine-worthy.
''';

    if (colorPalette != null) {
      prompt += '\nColor palette: $colorPalette';
    }
    if (additionalDetails != null) {
      prompt += '\n$additionalDetails';
    }

    prompt += '''
\nShot on a wide-angle lens, professional staging, warm ambient lighting.
4K quality, architectural digest style photography.
''';

    return prompt;
  }
}
