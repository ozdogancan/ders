import re

with open('lib/views/home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Swap RecentChats and Style Explore manually using string find/replace to be 100% safe
# We find the blocks using simple text matches

# find the start and end of _RecentChats
recent_start = text.find('                  // Son Sohbetler')
if recent_start == -1:
    recent_start = text.find('                  SliverToBoxAdapter(\n                    child: _staggered(\n                      1,\n                      _RecentChats(')

# find the start of Stilini Kesfet
style_start = text.find('                  SliverToBoxAdapter(\n                    child: _staggered(\n                      2,\n                      _section(\n                        \'Stilini Keşfet\'')

# find the end of Stilini Kesfet (which ends after the ListView blocks)
# Look for the start of the next section "Sana Nasil"
next_section_start = text.find('                  // SECTION 3: Evlumba Servisleri')
if next_section_start == -1:
    next_section_start = text.find('                  SliverToBoxAdapter(\n                    child: _staggered(\n                      3,\n                      _section(\n                        \'Sana Nasıl Yardımcı Olabilirim?\'')

if recent_start != -1 and style_start != -1 and next_section_start != -1:
    recent_str = text[recent_start:style_start]
    style_str = text[style_start:next_section_start]
    
    # Adjust staggered indices:
    # recent was 1, make it 2.
    new_recent_str = recent_str.replace('_staggered(\n                      1,', '_staggered(\n                      2,')
    # style was 2, make it 1.
    new_style_str = style_str.replace('_staggered(\n                      2,', '_staggered(\n                      1,')
    
    text = text[:recent_start] + new_style_str + new_recent_str + text[next_section_start:]
    print("Swapped RecentChats and StyleExplore successfully")
else:
    print("Failed to find blocks to swap")
    print(recent_start, style_start, next_section_start)


# Update _VerticalInspo to accept width
text = text.replace('  const _VerticalInspo({\n    required this.url,', '  const _VerticalInspo({\n    this.width = 180,\n    required this.url,')
text = text.replace('  final String url, label, sub;', '  final double width;\n  final String url, label, sub;')
text = text.replace('    child: Container(\n      width: defaultWidth ?? 180,', '    child: Container(\n      width: width,')
text = text.replace('    child: Container(\n      width: 180,', '    child: Container(\n      width: width,')

# Make the first card wider in Stilini Keşfet
target = """                            _VerticalInspo(
                              url:
                                  'https://images.unsplash.com/photo-1586023492125"""
replacement = """                            _VerticalInspo(
                              width: MediaQuery.of(context).size.width * 0.70,
                              url:
                                  'https://images.unsplash.com/photo-1586023492125"""
text = text.replace(target, replacement)

with open('lib/views/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print('Saved changes!')
