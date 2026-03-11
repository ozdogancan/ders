import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class MathTextBlock extends StatelessWidget {
  const MathTextBlock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final List<_Chunk> chunks = _parse(text);
    final TextStyle fallbackStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: chunks.map((chunk) {
        if (chunk.value.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        if (chunk.isLatex) {
          final cleaned = _cleanLatex(chunk.value);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                cleaned,
                textStyle: fallbackStyle.copyWith(fontSize: 18),
                mathStyle: chunk.isDisplay ? MathStyle.display : MathStyle.text,
                onErrorFallback: (error) {
                  // If LaTeX fails, try a simpler version
                  final simpler = _simplifyLatex(cleaned);
                  if (simpler != cleaned) {
                    return Math.tex(
                      simpler,
                      textStyle: fallbackStyle.copyWith(fontSize: 18),
                      onErrorFallback: (_) =>
                          Text(chunk.value, style: fallbackStyle),
                    );
                  }
                  return Text(chunk.value, style: fallbackStyle);
                },
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(chunk.value, style: fallbackStyle),
        );
      }).toList(),
    );
  }

  /// Parse input into chunks of text and LaTeX.
  /// Supports: $$..$$, $..$ and bare LaTeX patterns.
  List<_Chunk> _parse(String input) {
    final List<_Chunk> chunks = <_Chunk>[];

    // First handle $$ display math $$
    // Then handle $ inline math $
    // Combined regex: match $$...$$ or $...$
    final RegExp regex = RegExp(r'\$\$([^$]+)\$\$|\$([^$]+)\$');

    if (!input.contains(r'$')) {
      // No dollar signs - check for bare LaTeX commands
      if (_containsLatexCommands(input)) {
        return <_Chunk>[_Chunk(value: input, isLatex: true, isDisplay: false)];
      }
      return <_Chunk>[_Chunk(value: input, isLatex: false)];
    }

    int cursor = 0;

    for (final Match match in regex.allMatches(input)) {
      if (match.start > cursor) {
        final before = input.substring(cursor, match.start).trim();
        if (before.isNotEmpty) {
          chunks.add(_Chunk(value: before, isLatex: false));
        }
      }

      // Group 1 = display math ($$...$$), Group 2 = inline math ($...$)
      final bool isDisplay = match.group(1) != null;
      final String latex = (match.group(1) ?? match.group(2) ?? '').trim();
      if (latex.isNotEmpty) {
        chunks.add(_Chunk(value: latex, isLatex: true, isDisplay: isDisplay));
      }
      cursor = match.end;
    }

    if (cursor < input.length) {
      final remaining = input.substring(cursor).trim();
      if (remaining.isNotEmpty) {
        chunks.add(_Chunk(value: remaining, isLatex: false));
      }
    }

    return chunks;
  }

  /// Check if text contains LaTeX commands without dollar signs
  bool _containsLatexCommands(String text) {
    return text.contains(r'\frac') ||
        text.contains(r'\sqrt') ||
        text.contains(r'\times') ||
        text.contains(r'\div') ||
        text.contains(r'\Rightarrow') ||
        text.contains(r'\implies') ||
        text.contains(r'\left') ||
        text.contains(r'\right') ||
        text.contains(r'\overline') ||
        text.contains(r'\sum') ||
        text.contains(r'\int') ||
        text.contains(r'\lim') ||
        text.contains(r'\infty') ||
        text.contains(r'\pi') ||
        text.contains(r'\alpha') ||
        text.contains(r'\beta') ||
        text.contains(r'\theta') ||
        text.contains(r'\geq') ||
        text.contains(r'\leq') ||
        text.contains(r'\neq') ||
        text.contains(r'\cdot') ||
        text.contains(r'\pm');
  }

  /// Clean and fix LaTeX string for flutter_math_fork compatibility.
  static String _cleanLatex(String s) {
    var result = s.trim();

    // Remove wrapping dollar signs
    result = result.replaceAll(RegExp(r'^\$+|\$+$'), '');

    // ═══ RESCUE: fix broken commands where backslash was eaten ═══
    result = result.replaceAllMapped(RegExp(r'(?<!\\)rac\{'), (_) => r'\frac{');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)cdot(?![a-zA-Z])'), (_) => r'\cdot');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)times(?![a-zA-Z])'), (_) => r'\times');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)div(?![a-zA-Z])'), (_) => r'\div');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)sqrt\{'), (_) => r'\sqrt{');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)Rightarrow(?![a-zA-Z])'), (_) => r'\Rightarrow');
    result = result.replaceAllMapped(RegExp(r'(?<!\\)quad(?![a-zA-Z])'), (_) => r'\quad');

    // ── Unsupported commands → supported equivalents ──

    // \implies → \Rightarrow
    result = result.replaceAll(r'\implies', r'\Rightarrow');

    // \newline → space (flutter_math doesn't support line breaks)
    result = result.replaceAll(r'\newline', ' \\quad ');
    // Standalone \\ (line break, NOT part of a command like \\frac)
    // Only match \\ followed by space, end of string, or non-letter
    if (!result.contains(r'\begin{')) {
      result = result.replaceAllMapped(
        RegExp(r'\\\\(?![a-zA-Z])'),
        (_) => ' \\quad ',
      );
    }

    // \text{...} → \mathrm{...} (flutter_math_fork supports \mathrm better)
    result = result.replaceAllMapped(
      RegExp(r'\\text\{([^}]*)\}'),
      (m) => '\\mathrm{${m.group(1)}}',
    );

    // \textbf{...} → \mathbf{...}
    result = result.replaceAllMapped(
      RegExp(r'\\textbf\{([^}]*)\}'),
      (m) => '\\mathbf{${m.group(1)}}',
    );

    // \boxed{...} → content (flutter_math_fork may not support)
    result = result.replaceAllMapped(
      RegExp(r'\\boxed\{([^}]*)\}'),
      (m) => m.group(1) ?? '',
    );

    // \cancel{...} → content
    result = result.replaceAllMapped(
      RegExp(r'\\cancel\{([^}]*)\}'),
      (m) => m.group(1) ?? '',
    );

    // \displaystyle → remove (already display mode)
    result = result.replaceAll(r'\displaystyle', '');

    // \, \; \! \: → thin spaces or remove
    result = result.replaceAll(r'\,', ' ');
    result = result.replaceAll(r'\;', ' ');
    result = result.replaceAll(r'\!', '');
    result = result.replaceAll(r'\:', ' ');

    // Turkish characters in LaTeX → transliterate for math mode
    result = result.replaceAll('ı', 'i');
    result = result.replaceAll('İ', 'I');
    result = result.replaceAll('ğ', 'g');
    result = result.replaceAll('Ğ', 'G');
    result = result.replaceAll('ü', 'u');
    result = result.replaceAll('Ü', 'U');
    result = result.replaceAll('ş', 's');
    result = result.replaceAll('Ş', 'S');
    result = result.replaceAll('ö', 'o');
    result = result.replaceAll('Ö', 'O');
    result = result.replaceAll('ç', 'c');
    result = result.replaceAll('Ç', 'C');

    // Clean up multiple spaces
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');

    return result.trim();
  }

  /// Last-resort simplification: strip all unknown commands
  static String _simplifyLatex(String s) {
    var result = s;

    // Remove any remaining unknown \command that isn't standard
    final knownCommands = {
      'frac', 'sqrt', 'times', 'div', 'cdot', 'pm', 'mp',
      'Rightarrow', 'Leftarrow', 'leftrightarrow',
      'leq', 'geq', 'neq', 'approx', 'equiv',
      'sum', 'prod', 'int', 'lim', 'log', 'ln', 'sin', 'cos', 'tan',
      'alpha', 'beta', 'gamma', 'delta', 'theta', 'pi', 'phi', 'omega',
      'infty', 'partial',
      'left', 'right', 'big', 'Big', 'bigg', 'Bigg',
      'overline', 'underline', 'hat', 'bar', 'vec', 'dot',
      'mathrm', 'mathbf', 'mathit', 'mathbb', 'mathcal',
      'quad', 'qquad',
      'begin', 'end',
      'binom', 'choose',
    };

    result = result.replaceAllMapped(
      RegExp(r'\\([a-zA-Z]+)'),
      (m) {
        final cmd = m.group(1)!;
        if (knownCommands.contains(cmd)) return m.group(0)!;
        // Unknown command → remove the backslash, keep text
        return cmd;
      },
    );

    return result;
  }
}

class _Chunk {
  const _Chunk({required this.value, required this.isLatex, this.isDisplay = false});

  final String value;
  final bool isLatex;
  final bool isDisplay;
}
