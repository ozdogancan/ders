
import re

with open('lib/views/home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# I will find the RecentChats block and remove it:
recent_block = re.search(r'(\s*SliverToBoxAdapter\(\s*child:\s*_staggered\(\s*1,\s*_RecentChats\(.*?\),\s*\),\s*\),\s*)', text, re.DOTALL)
if recent_block:
    recent_str = recent_block.group(1)
    text = text.replace(recent_str, '')
    
    # Now find where the ListView ends. It ends around the SliverToBoxAdapter for 'Sana Nasıl Yardımcı Olabilirim?' block.
    # We will insert recent_str RIGHT BEFORE the 'Sana Nasıl Yardımcı Olabilirim?' block.
    insert_marker = r' *SliverToBoxAdapter\(\s*child: _staggered\(\s*3,\s*_section\(\s*\'Sana'
    new_text = re.sub(f'({insert_marker})', lambda m: recent_str.replace('1,', '2,') + m.group(1), text)
    
    if new_text != text:
        with open('lib/views/home_screen.dart', 'w', encoding='utf-8') as f:
            f.write(new_text)
        print('Swapped successfully')
    else:
        print('Failed to swap - insertion point not found')
else:
    print('Failed to swap - recent block not found')

