alias brewup="brew update && brew upgrade"

# Source local machine-specific config (loaded last so local overrides win)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
