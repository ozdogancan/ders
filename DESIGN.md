# Koala DESIGN.md

Living record of **decisions**, not rules. For rules see `CLAUDE.md`.
Each entry answers four questions: *what problem, what we chose, what we
rejected, how we know it's done.*

---

## Fix #1 — Hero tag safety (no code fix required)

**Problem:** Duplicate `Hero` tag risk suspected between the deck's top
card and the peek overlay (same tag `swipe-hero-<cardId>`).

**Karar:** No runtime bug after close inspection. The top card's Hero
guard (`isTop && !isExiting && !_peekActive`) is mutually exclusive with
the peek overlay's render guard (`_peekActive == true`). Within any
single build pass at most one Hero with that tag exists. Home → /swipe
route transition uses matching tags *intentionally* — that is how Hero
flight works.

**Aksiyon:** Inline comment in `feed_swipe_deck.dart` explaining the
invariant so future refactors don't break it.

---

## Fix #2 — Chat → Swipe trigger

**Problem:** The Koala AI chat is siloed from the swipe feed. A user
conversing about "minimalist salon istiyorum" has no inline path to
trigger taste-calibration.

**Karar:** Add a `ChatSwipeInvite` widget shown as the **empty-state
leading card** of a chat conversation. Title invites the user to a
quick taste calibration; primary button pushes `/swipe` via
`context.push('/swipe')`. Smart AI-driven triggering (tool-call,
heuristic placement mid-conversation) is explicitly v2.

**Reddedilenler:**
- Inline mini-deck (3 cards in chat bubble) — steals conversation
  attention, dwell tracking impossible inside a bubble.
- Auto-redirect to `/swipe` — hijacks UX, loses chat context.
- Persistent floating swipe button on chat — noise, not contextual.

**Kabul kriteri:**
- [ ] New widget `ChatSwipeInvite` renders in chat when user has zero
      messages in the conversation.
- [ ] Tap → `context.push('/swipe')`.
- [ ] Analytics: `chat_swipe_invite_shown` (once per mount),
      `chat_swipe_invite_tapped` on button press.

**Dosyalar:**
- NEW: `lib/widgets/chat/chat_swipe_invite.dart`
- `lib/views/chat_detail_screen.dart` (render invite in empty state)

---

## Fix #3 — Peek reveals context

**Problem:** Long-press peek just scales the card. No new information
— cosmetic, missed discovery opportunity.

**Karar:** Peek overlay adds an **info panel** below the enlarged
card: designer avatar + name, optional room type chip, 2–3 style
tags, and an optional horizontal strip of 3 similar cards (only when
the `similar_card_ids` field is non-empty). Graceful null handling
for cards that lack any of these fields.

**Reddedilenler:**
- Full product detail page — overkill, breaks peek's "quick glance" contract.
- Related cards grid (12+) — too many, distracts from the primary card.
- Dominant-color palette extraction — expensive on web, ships later.

**Kabul kriteri:**
- [ ] `_PeekOverlay` shows enlarged card + info panel underneath.
- [ ] Panel degrades gracefully when designer/tags/similar are null.
- [ ] Scrim tap still dismisses peek. Action chips unchanged.

**Dosyalar:**
- `lib/models/koala_card.dart` (extend with `designerName`, `designerAvatarUrl`, `roomType`, `styleTags`, `similarCardIds` — all nullable)
- `lib/widgets/swipe/feed_swipe_deck.dart` (`_PeekOverlay` gets info panel)

---

## Fix #4 — First-run onboarding

**Problem:** Up-swipe (save) and long-press peek are **invisible** to
new users. No discovery mechanism.

**Karar:** One-time coachmark overlay on first visit to `/swipe`
(not home hero deck — home is ambient, too aggressive for a tutorial).
Three sequential tooltips with arrow indicators: **Sağa beğen → / ←
Sola geç / ↑ Yukarı kaydet**. Dismissible via **Anladım** at any step.
Flag persisted as `koala.swipe_onboarding_seen.v1` in
SharedPreferences.

**Reddedilenler:**
- Ghost-swipe demo (card auto-moves) — too magical, unclear what's
  happening.
- Permanent inline hint strip at card bottom — sticky noise for
  experts.
- Modal dialog before any swipe — friction, breaks into the product.

**Kabul kriteri:**
- [ ] First mount of `SwipeScreen` checks SharedPreferences flag.
- [ ] If unseen → overlay appears; steps through 3 tooltips.
- [ ] Once dismissed, flag persists, overlay never shows again.
- [ ] No disruption to swipe gestures while overlay is active
      (overlay absorbs taps, deck beneath is paused).

**Dosyalar:**
- NEW: `lib/widgets/swipe/swipe_onboarding_overlay.dart`
- `lib/views/swipe_screen.dart` (mount overlay conditionally)

---

## Fix #5 — Ring transparency

**Problem:** Footer labels "SENİN İÇİN / KEŞFET / YENİ / NADİR" are
jargon. User doesn't know **why** this card surfaced.

**Karar:** Add a secondary explanation line below the ring label,
derived **client-side** from `card.ring`. Plain Turkish. No server
change (server doesn't yet emit explanations — that's v2).

Mapping:
- `exploit` → "Beğenilerine yakın bir öneri"
- `explore` → "Keşfetmeni istediğimiz bir yön"
- `fresh`   → "Yeni gelen kartlardan"
- `rare`    → "Az görülen bir kart"
- unknown   → hide secondary line

**Reddedilenler:**
- Server-provided per-card explanation — requires RPC change, ships
  later.
- Tooltip on tap — fragments attention mid-swipe.
- Always-visible hover text — no hover on mobile web.

**Kabul kriteri:**
- [ ] `_QueueHint` renders primary (ring label) + secondary (reason).
- [ ] Secondary line smaller, lighter, same letter-spacing.
- [ ] Falls back gracefully when ring is unknown.

**Dosyalar:**
- `lib/views/swipe_screen.dart` (`_QueueHint`)
