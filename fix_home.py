import re

with open('lib/views/home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add Platform import if missing
if 'import \'dart:io\'' not in text:
    text = text.replace('import \'dart:async\';', 'import \'dart:async\';\nimport \'dart:io\' show Platform;')

# 2. Physics changes
text = re.sub(
    r'physics:\s*const\s*AlwaysScrollableScrollPhysics\(\s*parent:\s*BouncingScrollPhysics\(\),\s*\)',
    'physics: AlwaysScrollableScrollPhysics(parent: Platform.isIOS ? const BouncingScrollPhysics() : const ClampingScrollPhysics())',
    text
)
text = text.replace('physics: const BouncingScrollPhysics()', 'physics: Platform.isIOS ? const BouncingScrollPhysics() : const ClampingScrollPhysics()')

# 3. Input bar fixes
# Add TextEditingController to State if missing
if '_inputCtrl' not in text:
    text = re.sub(r'(class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin \{)',
                  r'\1\n  final TextEditingController _inputCtrl = TextEditingController();', 
                  text)
    text = re.sub(r'(super\.dispose\(\);\s*\})',
                  r'  _inputCtrl.dispose();\n    \1',
                  text)

# Replace the AbsorbPointer + readOnly TextField:
old_input = '''                child: AbsorbPointer(
                  child: TextField(
                    readOnly: true,
                    showCursor: false,'''
new_input = '''                child: TextField(
                  controller: _inputCtrl,
                  readOnly: false,
                  showCursor: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      _openChat(text: val);
                      _inputCtrl.clear();
                    }
                  },'''
text = text.replace(old_input, new_input)
# Also remove the GestureDetector wrapper navigating immediately to ChatDetailScreen for the Expanded child
text = re.sub(r'GestureDetector\s*\(\s*onTap:\s*\(\)\s*=>\s*Navigator\.of\(context\)\.push\(\s*MaterialPageRoute\(builder:\s*\(_\)\s*=>\s*const ChatDetailScreen\(\)\),\s*\),\s*child:\s*(TextField\()',
              r'\1', text)

# 4. Hero Card Responsive scaling
# We replace hardcoded 24 padding with LayoutBuilder
hero_pattern = r'(Container\(\s*width:\s*double.infinity,\s*padding:\s*)const EdgeInsets\.all\(24\)(,\s*decoration:\s*BoxDecoration\()'
text = re.sub(hero_pattern, r'\1EdgeInsets.all(MediaQuery.of(context).size.width * 0.06)\2', text)

# Hero icon responsive
hero_icon_pattern = r'(Icons\.auto_awesome_rounded,\s*size:\s*)120(,)'
text = re.sub(hero_icon_pattern, r'\1MediaQuery.of(context).size.width * 0.28\2', text)

# Hero position rights
text = re.sub(r'right:\s*-25,\s*top:\s*-25,', r'right: -MediaQuery.of(context).size.width * 0.05,\n                                      top: -MediaQuery.of(context).size.width * 0.05,', text)


# 5. Empty State for RecentChats
empty_state_old = '''    if (_chats.isEmpty) return const SizedBox.shrink();'''
empty_state_new = '''    if (_chats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F1FA).withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.sparkles, size: 18, color: Colors.grey),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Henüz bir hikaye yaratmadık. Seni dinlemek için buradayım...',
                  style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
      );
    }'''
text = text.replace(empty_state_old, empty_state_new)

# 6. Swap Recent Chats and Style Explore sections
# Currently, _staggered calls inside CustomScrollView are sequential. Let's just find the whole sliver blocks and swap them!
# We don't need to do it precisely because we can just change the index in staggered if we want, but visually we just swap their positions.
# They are both SliverToBoxAdapter. We can find the blocks.
recent_chats_block = r'''                  SliverToBoxAdapter\(
                    child: _staggered\(
                      1,
                      _RecentChats\(.+?\),\n                      \),\n                    \),\n                  \),'''

# The Style block spans from _section up to the end of ListView
style_block_re = r'''(                  SliverToBoxAdapter\(\s*child: _staggered\(\s*2,\s*_section\(\s*'Stilini Keşfet'.+?SliverToBoxAdapter\(\s*child: _staggered\(\s*2,\s*SizedBox\(\s*height: 280,.+?_VerticalInspo\(.+?\]\s*,\s*\)\s*,\s*\)\s*,\s*\)\s*,\s*\)\s*,)'''

# Using a simpler approach: Just look for section titles or use multi_replace manually inside the IDE.
# ACTUALLY, I will skip section swapping in Python regex to avoid breaking the tree, I will do it with multi_replace_file_content!

# 7. Use LucideIcons for premium feel!
text = text.replace('import \'package:flutter/material.dart\';', 'import \'package:flutter/material.dart\';\nimport \'package:lucide_icons/lucide_icons.dart\';')
# Replace known material icons with Lucide (only those explicitly used in HomeScreen)
icon_replacements = {
    'Icons.person_rounded': 'LucideIcons.user',
    'Icons.chat_bubble_outline_rounded': 'LucideIcons.messageCircle',
    'Icons.camera_alt_rounded': 'LucideIcons.camera',
    'Icons.photo_library_rounded': 'LucideIcons.image',
    'Icons.arrow_forward_rounded': 'LucideIcons.arrowRight',
    'Icons.shopping_bag_rounded': 'LucideIcons.shoppingBag',
    'Icons.person_search_rounded': 'LucideIcons.search',
    'Icons.palette_rounded': 'LucideIcons.palette',
    'Icons.arrow_upward_rounded': 'LucideIcons.arrowUp',
    'Icons.auto_awesome_rounded': 'LucideIcons.sparkles',
    'Icons.auto_awesome_outlined': 'LucideIcons.sparkles',
    'Icons.chat_bubble_rounded': 'LucideIcons.messageSquare',
    'Icons.chevron_right_rounded': 'LucideIcons.chevronRight',
}
for mat_icon, lucide in icon_replacements.items():
    text = text.replace(mat_icon, lucide)

with open('lib/views/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('done layout fixes')
