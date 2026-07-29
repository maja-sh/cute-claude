# @build:strip-begin
# The critter table — the file to edit when adding a critter. Inlined verbatim
# into the installer at build time; it is shell source, not a heredoc body.
# @build:strip-end
# Per-critter flavor and palette. FACE/BLINK are the statusline buddy and its
# blink frame — keep the pair the same display width or the statusline jitters.
# T_* feed the terminal theme; see write_theme.
case "$CRITTER" in
  cat|catgirl)
    CRITTER="cat"; EMOJI="🐈"
    FLAVOR="nya, mrrp, paws, ฅ, tail, ears, purring, headpats"
    FACE="ฅ^•ﻌ•^ฅ"; BLINK="ฅ^˘ﻌ˘^ฅ"
    VERBS='["Purring","Loafing","Kneading","Blinking slowly","Making biscuits","Aggressively napping","Sitting in a box","Doing a mlem","Toe-beaning","Zoomying","Trilling","Mrrping","Nyaing","Pouncing","Being perceived","Knocking it off the table","Sploot-ing","Headbutting","Booping","Meowing at nothing","Loafing harder"]'
    T_MAIN="#f9a8d4"; T_TEXT="#c4b5fd"; T_BRIGHT="#ec4899"; T_ALT="#d946ef"
    T_COOL="#93c5fd"; T_DEEP="#8b5cf6"
    T_BG="#1e1633"; T_BG2="#2a1f47"; T_BG3="#17131f"; T_MEM="#2a1a3e"; T_SEL="#6d28d9"
    ;;
  bnuuy|bunny)
    CRITTER="bnuuy"; EMOJI="🐇"
    FLAVOR="hops, floppy ears, bnuuy noises, (・×・), nose twitches, binkies, headpats"
    FACE="/(•×•)\\"; BLINK="/(˘×˘)\\"
    VERBS='["Binkying","Nose twitching","Flopping over","Doing a zoomie","Loafing","Thumping","Nibbling","Hopping","Perking up","Snuffling","Bnuuying","Disapproving quietly","Hiding under the furniture","Being fluffy","Chinning everything","Periscoping","Dead-bnuuy flopping","Wiggling","Munching","Ear-swiveling","Flopping harder"]'
    T_MAIN="#fda4af"; T_TEXT="#fecdd3"; T_BRIGHT="#fb7185"; T_ALT="#f472b6"
    T_COOL="#fcd5ce"; T_DEEP="#e11d48"
    T_BG="#2a1a1f"; T_BG2="#3a2429"; T_BG3="#1c1417"; T_MEM="#2e1c22"; T_SEL="#9f1239"
    ;;
  fox|foxgirl)
    CRITTER="fox"; EMOJI="🦊"
    FLAVOR="yips, tail swish, ears, a lil mischief, headpats"
    FACE="(•ω•)~"; BLINK="(˘ω˘)~"
    VERBS='["Yipping","Tail swishing","Pouncing","Scheming","Skulking","Digging","Screaming into the void","Sniffing","Trotting","Being sly","Curling up","Ear swiveling","Stealing something","Chittering","Bouncing","Denning","Zoomying","Nose booping","Tail wrapping","Yowling","Scheming harder"]'
    T_MAIN="#fdba74"; T_TEXT="#fed7aa"; T_BRIGHT="#f97316"; T_ALT="#fb923c"
    T_COOL="#fcd34d"; T_DEEP="#c2410c"
    T_BG="#2a1c10"; T_BG2="#3a2717"; T_BG3="#1c1409"; T_MEM="#2e2011"; T_SEL="#92400e"
    ;;
  raven|crow|corvid)
    CRITTER="raven"; EMOJI="🪶"
    FLAVOR="caws, head tilts, hops, shiny things, ruffled feathers, an uncanny memory for faces"
    FACE="(•▾•)"; BLINK="(˘▾˘)"
    VERBS='["Cawing","Collecting shiny things","Tilting head","Cracking a nut","Mimicking","Hoarding","Remembering your face","Testing a tool","Perching","Judging silently","Croaking","Hopping","Preening","Sizing you up","Ruffling feathers","Dropping a stick","Stashing something","Watching","Corvid-ing","Unwrapping a puzzle","Scheming harder"]'
    T_MAIN="#a5b4fc"; T_TEXT="#cbd5e1"; T_BRIGHT="#818cf8"; T_ALT="#a78bfa"
    T_COOL="#94a3b8"; T_DEEP="#4338ca"
    T_BG="#16181d"; T_BG2="#212530"; T_BG3="#111318"; T_MEM="#1b1e27"; T_SEL="#3730a3"
    ;;
  *)
    EMOJI="✨"
    # No hardcoded flavor for a critter we have never heard of — the file is read
    # by Claude, so the sensible generator is Claude. It improvises from the name.
    FLAVOR="improvise it — invent this critter's noises, gestures and little habits from its name, then keep them consistent"
    _pick="${FACE_POOL[$(( $(name_hash "$CRITTER") % ${#FACE_POOL[@]} ))]}"
    FACE="${_pick%%|*}"; BLINK="${_pick##*|}"
    VERBS='["Thinking","Pondering","Noodling","Wiggling","Vibing","Puttering","Fidgeting","Humming","Doodling","Musing","Tinkering","Bumbling","Wandering","Percolating","Idling","Rummaging","Daydreaming","Shuffling","Blinking","Stretching","Vibing harder"]'
    T_MAIN="#c4b5fd"; T_TEXT="#ddd6fe"; T_BRIGHT="#a78bfa"; T_ALT="#67e8f9"
    T_COOL="#93c5fd"; T_DEEP="#7c3aed"
    T_BG="#1a1726"; T_BG2="#262133"; T_BG3="#14121c"; T_MEM="#221c33"; T_SEL="#5b21b6"
    ;;
esac
