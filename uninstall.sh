#!/bin/bash
# Удаление DeckVoice. Рантайм (модели, библиотеки) НЕ трогает — удали вручную,
# если он больше не нужен: rm -rf ~/.local/share/deck-voice
set -e
rm -f "$HOME/.local/bin/deck-dictation"
rm -f "$HOME/.local/share/applications/deck-voice-toggle.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Ярлык и команда удалены."
echo "Оставлено намеренно:"
echo "  ~/.config/deck-voice/       настройки"
echo "  ~/.local/state/deck-voice/  логи"
echo "  ~/.local/share/deck-voice/  модели и библиотеки ($(du -sh "$HOME/.local/share/deck-voice" 2>/dev/null | cut -f1))"
echo "  ydotoold.service            может использоваться другими программами"
