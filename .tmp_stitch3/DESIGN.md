# Design System Document: Editorial Interior Luxury

## 1. Overview & Creative North Star: "The Curated Sanctuary"
This design system moves away from the rigid, boxed-in nature of traditional mobile apps, leaning instead into the world of high-end editorial magazines. The Creative North Star is **"The Curated Sanctuary"**—a digital space that feels as intentional, tactile, and calm as a well-designed home.

To achieve a "bespoke" feel, we reject standard templates. We utilize **intentional asymmetry**, allowing images to break the grid, and **tonal depth**, where elements feel layered like fine linens rather than static pixels. The interface should feel "airy," prioritizing white space as a luxury material itself.

---

## 2. Colors & Surface Philosophy
The palette is rooted in Mediterranean earthiness and Turkish residential warmth. It avoids the clinical "tech blue" in favor of organic, muted tones.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to define sections. We define boundaries through:
1.  **Background Shifts:** Transitioning from `surface` (#fcf9f4) to `surface-container-low` (#f6f3ee).
2.  **Tonal Transitions:** Using the `surface-container` tiers to create logical groupings.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. Use the following logic for stacking:
*   **Base Layer:** `surface` (#fcf9f4) for the main canvas.
*   **Secondary Content Areas:** `surface-container-low` (#f6f3ee) for large background sections (e.g., a "Recommended" section).
*   **Interactive Components:** `surface-container-lowest` (#ffffff) for cards and input fields to make them "pop" subtly against the warmer background.

### The "Glass & Soul" Rule
While we avoid "cold" glassmorphism, we use **"Warm Glass"** for floating navigation bars or overlays. Use `surface` at 80% opacity with a `20px` backdrop blur. To add "soul," use a very subtle linear gradient on main CTAs, transitioning from `primary` (#554362) to `primary-container` (#6e5a7b) to give buttons a gentle, three-dimensional curve.

---

## 3. Typography: The Editorial Voice
Our typography is a conversation between heritage and modernity.

*   **Display & Headlines (Noto Serif):** These are our "Brand Moments." Use `display-lg` for editorial headers and `headline-md` for section titles. The serif typeface conveys intelligence and the "Modern Turkish Lifestyle" influence.
*   **UI & Body (Manrope):** A clean, humanist sans-serif. It provides clarity without feeling industrial. Use `body-lg` for descriptions and `label-md` for functional metadata.
*   **Hierarchy Note:** High contrast in scale is encouraged. A `display-sm` headline next to a `label-sm` caption creates an "expensive" editorial look.

---

## 4. Elevation & Depth
Depth is achieved through **Tonal Layering** rather than traditional drop shadows.

*   **The Layering Principle:** Instead of a shadow, place a `surface-container-lowest` card on a `surface-container` background. The slight shift in hex value provides a sophisticated, "quiet" lift.
*   **Ambient Shadows:** For floating elements (e.g., a "Book Consultant" FAB), use a custom shadow: 
    *   *Y: 12px, Blur: 24px, Color:* `on-surface` (#1c1c19) at **4% opacity**.
    *   This mimics natural light hitting a matte surface.
*   **The "Ghost Border" Fallback:** If a border is required for accessibility, use `outline-variant` (#ccc4cd) at **15% opacity**. Never use a 100% opaque border.

---

## 5. Components

### Buttons & Interaction
*   **Primary Action:** Rounded corners (`xl` 1.5rem). Background: `primary` (#554362). Text: `on-primary` (#ffffff). Apply a subtle 10% vertical gradient to simulate a soft tactile press.
*   **Secondary/Positive:** Used for "Success" or "Save" actions. Use `secondary` (#466558) with `on-secondary` text.
*   **Tertiary:** No background. Text in `primary`. Use for low-emphasis actions like "View More."

### Input Fields
*   **Style:** Minimalist. No bottom line. Use a `surface-container-highest` (#e5e2dd) background with `xl` (1.5rem) rounded corners.
*   **States:** On focus, the background shifts to `surface-container-lowest` (#ffffff) with a 20% `primary` "Ghost Border."

### Cards & Editorial Modules
*   **The Content Card:** Strictly no dividers. Use vertical spacing (Scale `8` - 2.75rem) to separate the image, headline, and body.
*   **Asymmetric Layouts:** For inspiration galleries, mix card widths (e.g., one card at 60% width, the next at 40%) to mimic a lifestyle magazine layout.

### Specialized Components: "The Fabric Swatch"
*   **Material Preview Chips:** For interior design apps, use `xl` rounded chips that contain both a color hex and a subtle texture overlay to represent wood, marble, or textile.

---

## 6. Do’s and Don’ts

### Do:
*   **Embrace the Void:** Use the `spacing-12` (4rem) or `spacing-16` (5.5rem) values generously between major sections.
*   **Layer with Intent:** Ensure that every "layer" has a logical reason for being higher in the surface hierarchy.
*   **Curate Imagery:** Use high-quality photography with warm, natural lighting. UI should "wrap" around the photography.

### Don't:
*   **Don't Use Dividers:** Never use a horizontal line to separate content. Use a `2rem` (Scale 6) space or a change in `surface-container` color instead.
*   **Don't Use Pure Black:** Use `on-surface` (#1c1c19) for text to maintain the "Soft Luxury" warmth.
*   **Don't Rush the Eye:** Avoid busy animations. Use slow, ease-in-out transitions (300ms+) for a calm, premium feel.
*   **Don't Use Sharp Corners:** Every element must use at least `lg` (1rem) or `xl` (1.5rem) rounding to maintain the "Soft Minimalism" aesthetic.