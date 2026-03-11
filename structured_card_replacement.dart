// ══════════════════════════════════════════════════
// BU DOSYANIN ICERIGINI chat_screen.dart'taki
// _structuredCard FONKSIYONUNUN YERINE YAPISTIRINIZ
// Eski fonksiyon: "Widget _structuredCard(StructuredAnswer a) {" ile baslar
// "Widget _ratingWidget" satirindan onceki "}" ile biter
// ══════════════════════════════════════════════════

  Widget _structuredCard(StructuredAnswer a) {
    const colors = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899)];
    final isProblem = a.questionType == 'problem';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TUTOR HEADER
          Row(children: [
            _avatar(36),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                tutorNameForSubject(_q?.subject ?? 'Matematik'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withAlpha(15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('\u00c7\u00f6z\u00fcm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
            ),
          ]),
          const SizedBox(height: 14),

          // ── SUMMARY
          if (a.summary.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(a.summary, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF475569), height: 1.5)),
            ),

          // ── PROBLEM: VERILENLER
          if (isProblem && a.givenData != null && a.givenData!.isNotEmpty && a.givenData!.any((g) => g.trim().isNotEmpty))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u{1F4CB} VER\u0130LENLER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF), letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  ...a.givenData!.where((g) => g.trim().isNotEmpty).map((gItem) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('\u2022 $gItem', style: const TextStyle(fontSize: 13, color: Color(0xFF1E40AF), height: 1.4)),
                  )),
                ],
              ),
            ),

          // ── PROBLEM: ISTENEN
          if (isProblem && a.findData != null && a.findData!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u{1F3AF} \u0130STENEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF991B1B), letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(a.findData!, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), height: 1.4)),
                ],
              ),
            ),

          // ── PROBLEM: DENKLEM
          if (isProblem && a.modelEquation != null && a.modelEquation!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u{1F9EE} DENKLEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF166534), letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Math.tex(
                        _cleanLatex(a.modelEquation!),
                        textStyle: const TextStyle(fontSize: 16, color: Color(0xFF166534)),
                        mathStyle: MathStyle.display,
                        onErrorFallback: (_) => Text(a.modelEquation!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── STEPS
          ...a.steps.asMap().entries.map((e) {
            final i = e.key;
            final step = e.value;
            final sc = colors[i % colors.length];
            final isCrit = step.isCritical;
            final critColor = const Color(0xFFF59E0B);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kilit Adim etiketi
                if (isCrit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: critColor, borderRadius: BorderRadius.circular(6)),
                      child: const Text('\u26a1 Kilit Ad\u0131m', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),

                // Step kart
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isCrit ? critColor : sc.withAlpha(30), width: isCrit ? 2 : 1),
                    boxShadow: [BoxShadow(color: (isCrit ? critColor : sc).withAlpha(isCrit ? 12 : 8), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Adim numarasi + aciklama
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: (isCrit ? critColor : sc).withAlpha(20)),
                            child: Center(child: Text('${i + 1}', style: TextStyle(color: isCrit ? critColor : sc, fontSize: 13, fontWeight: FontWeight.w800))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _renderMixedText(step.explanation)),
                        ],
                      ),

                      // Reasoning - SADECE kilit adimda
                      if (isCrit && step.reasoning != null && step.reasoning!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          margin: const EdgeInsets.only(left: 40),
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEFCE8),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            border: Border(left: BorderSide(color: Color(0xFFFBBF24), width: 3)),
                          ),
                          child: Text.rich(TextSpan(children: [
                            const TextSpan(text: '\u{1F4A1} Neden? ', style: TextStyle(fontWeight: FontWeight.w700, fontStyle: FontStyle.normal, fontSize: 11.5, color: Color(0xFF92400E))),
                            TextSpan(text: step.reasoning!, style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E), height: 1.5, fontStyle: FontStyle.italic)),
                          ])),
                        ),
                      ],

                      // Formula
                      if (step.formula != null && step.formula!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(left: 40),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: (isCrit ? critColor : sc).withAlpha(8), borderRadius: BorderRadius.circular(10)),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Math.tex(
                              _cleanLatex(step.formula!),
                              textStyle: TextStyle(fontSize: 16, color: isCrit ? critColor : sc),
                              mathStyle: MathStyle.display,
                              onErrorFallback: (_) => Text(
                                _cleanLatex(step.formula!),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isCrit ? critColor : sc, fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),

          // ── CEVAP
          if (a.finalAnswer.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF22C55E).withAlpha(10)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6366F1).withAlpha(25)),
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withAlpha(20)),
                  child: const Icon(Icons.check_rounded, size: 20, color: Color(0xFF22C55E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cevap', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(a.finalAnswer, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                    ],
                  ),
                ),
              ]),
            ),

          // ── ALTIN KURAL
          if (a.goldenRule != null && a.goldenRule!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFFFEF3C7), const Color(0xFFFDE68A).withAlpha(40)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFBBF24).withAlpha(30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(7)),
                    child: const Center(child: Text('\u{1F511}', style: TextStyle(fontSize: 13))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ALTIN KURAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFB45309), letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        Text(a.goldenRule!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78350F), height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── TIP
          if (a.tip != null && a.tip!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withAlpha(12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFBBF24).withAlpha(25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u{1F4AA}', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(a.tip!, style: const TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
