#!/bin/bash
lang=${1:-en}
f=/tmp/rec

echo "Whisper Recording in ${lang}..."
arecord -qfcd "$f.wav" &
read -rsn1
kill $! 2>/dev/null
wait

echo "Whisper Processing..."
mise exec python -c "whisper '$f.wav' --model tiny --language '$lang' -o /tmp -f txt --verbose False 2>/dev/null"
cat "$f.txt" | xclip -sel c
cat "$f.txt"
read -rsn1
