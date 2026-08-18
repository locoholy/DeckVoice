#!/bin/bash
# Самопроверка DeckVoice. Ничего не меняет, sudo не нужен.
G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'
ok(){ echo -e "  ${G}OK${N}   $1"; }
bad(){ echo -e "  ${R}FAIL${N} $1"; F=$((F+1)); }
warn(){ echo -e "  ${Y}--${N}   $1"; }
F=0
RUNTIME="$HOME/.local/share/deck-voice"

echo
echo "=== 1. Рантайм ==="
if [ -f "$RUNTIME/models/ggml-small.bin" ]; then
    ok "модель small на месте ($(du -h "$RUNTIME/models/ggml-small.bin" | cut -f1))"
else
    bad "нет $RUNTIME/models/ggml-small.bin"
fi
[ -d "$RUNTIME/pylib" ] && ok "python-библиотеки ($(du -sh "$RUNTIME/pylib" | cut -f1))" || bad "нет $RUNTIME/pylib"

echo
echo "=== 2. Python и whisper ==="
if PYTHONPATH="$RUNTIME/pylib" /usr/bin/python3 -c "import numpy, pywhispercpp" 2>/dev/null; then
    ok "pywhispercpp и numpy импортируются"
else
    bad "импорт не проходит → PYTHONPATH=$RUNTIME/pylib python3 -c 'import pywhispercpp'"
fi

echo
echo "=== 3. Вставка текста ==="
if pgrep -x ydotoold >/dev/null; then ok "ydotoold работает"; else bad "ydotoold не запущен → systemctl --user start ydotoold"; fi
[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket" ] && ok "сокет ydotool на месте" || bad "нет сокета ydotool"
[ -x "$HOME/.local/bin/ydotool" ] && ok "клиент ydotool на месте" || bad "нет ~/.local/bin/ydotool"

if qdbus6 org.kde.klipper /klipper getClipboardContents >/dev/null 2>&1 \
   || qdbus org.kde.klipper /klipper getClipboardContents >/dev/null 2>&1; then
    ok "Klipper отвечает (это замена wl-copy, его в SteamOS нет)"
else
    bad "Klipper не отвечает — текст будет некуда положить"
fi

echo
echo "=== 4. Микрофон ==="
S=$(pactl get-default-source 2>/dev/null)
[ -n "$S" ] && ok "источник: $S" || bad "источник по умолчанию не определён"
command -v parecord >/dev/null && ok "parecord есть" || warn "parecord нет, будет pw-record"

echo
echo "=== 5. Установка ==="
[ -x "$HOME/.local/bin/deck-dictation" ] && ok "команда deck-dictation доступна" || bad "не установлено → ./install.sh"
[ -f "$HOME/.local/share/applications/deck-voice-toggle.desktop" ] && ok "ярлык на месте" || warn "ярлыка нет"
[ -f "$HOME/.config/deck-voice/config" ] && ok "конфиг: ~/.config/deck-voice/config" || warn "конфига нет, работают умолчания"

if grep -q "deck-voice-toggle.desktop\|deck-dictation" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null; then
    ok "горячая клавиша назначена"
else
    warn "горячая клавиша не назначена — Параметры системы → Горячие клавиши"
fi

echo
echo "=== 6. Чтобы не мешало ==="
for junk in vocalinux.desktop voice-type.desktop; do
    if [ -f "$HOME/.config/autostart/$junk" ]; then
        bad "$junk всё ещё в автозапуске — лишний процесс"
    else
        ok "$junk из автозапуска убран"
    fi
done

echo
echo "=== 7. Последний запуск ==="
L="$HOME/.local/state/deck-voice/current.log"
if [ -f "$L" ]; then
    grep -E "TIME|ERROR|распознано" "$L" | tail -6 | sed 's/^/       /'
else
    warn "логов ещё нет — нажми кнопку и продиктуй что-нибудь"
fi

echo
[ "$F" -eq 0 ] && echo -e "${G}Всё в порядке.${N}" || echo -e "${R}Проблем: $F${N}"
echo
