# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes for other theme options.
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins for the full plugin list.
plugins=(git jsontools zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# User configuration

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# >>> fnm setup >>>
FNM_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
[[ -d "$FNM_INSTALL_DIR" ]] && export PATH="$FNM_INSTALL_DIR:$PATH"
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
unset FNM_INSTALL_DIR
# <<< fnm setup <<<
