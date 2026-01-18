#!/bin/sh

set -ex

HOME="${HOME:-~}"
REPO="https://github.com/mikecurtis/dotfiles"
BREWUSER="brewdog"

fail () {
  echo "$@" >&2
  exit 1
}

if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "${ID}" in
  arch | archarm)
    OS="arch"
    ;;
  ubuntu)
    OS="ubuntu"
    ;;
  esac
fi

if [ -z "$OS" ]; then
  if type uname >/dev/null 2>&1; then
    case "$(uname)" in
    Darwin)
      OS="macos"
      ;;
    esac
  fi
fi

if [ -z "$OS" ]; then
  fail "Unknown OS"
fi

confirm () {
  ${YES} && return
  read -p "$@ " choice
  case "$choice" in
  y | Y) return 0 ;;
  n | N) return 1 ;;
  *) confirm "$@" ;;
  esac
}

force () {
  ${FORCE} && return
  read -p "$@ " choice
  case "$choice" in
  y | Y) return 0 ;;
  n | N) return 1 ;;
  *) force "$@" ;;
  esac
}

check_which () {
  which $1 >/dev/null 2>&1
  return $?
}

install () {
  case "${OS}" in
  arch)
    sudo pacman --noconfirm --needed -Suy $* ||
      fail "${installer} install failed"
    ;;
  ubuntu)
    sudo apt update -y &&
      sudo apt install -y $* ||
      fail "apt install failed"
    ;;
  macos)
    if [ "${BREWUSER}" ]; then
      su -l ${BREWUSER} -c "brew update && brew install $*" ||
        fail "brew install failed"
    else
      brew update &&
        brew install $* ||
        fail "brew install failed"
    fi
    ;;
  esac
}

check_install () {
  if ! check_which $1; then
    if confirm "No $1 found.  Install?"; then
      install $1 || fail "$1 installation failed!"
    else
      fail "User aborted"
    fi
  fi
  check_which $1 || fail "No $1 found!"
}

check_install_mise () {
  if ! check_which mise; then
    if [ "${OS}" = "ubuntu" ]; then
      sudo install -dm 755 /etc/apt/keyrings
      curl -fSs https://mise.jdx.dev/gpg-key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
      echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list
    fi
    check_install mise
  fi
}

chsh_zsh () {
  shell=""
  if [ "${OS}" = "macos" ]; then
    shell="$(dscl . -read /Users/${USER} UserShell | awk '{print $2}' | awk -F/ '{print $NF}')"
  else
    shell="$(grep "^${USER}:" /etc/passwd | cut -d: -f7 | awk -F/ '{print $NF}')"
  fi
  if [ "${shell}" != "zsh" ]; then
    bin="$(grep zsh /etc/shells | head -1)"
    [ "${bin}" ] || die "Could not find zsh in /etc/shells"
    if sudo true 2>/dev/null; then
      sudo chsh -s ${bin} ${USER} || fail "Failed to sudo chsh"
    else
      chsh -s ${bin} || fail "Failed to chsh"
    fi
  fi
}

bootstrap_chezmoi () {
  mise use -g chezmoi || fail "chezmoi install failed"
  mise exec chezmoi -- chezmoi init ${REPO} || fail "could not init chezmoi"
  cmDir="$(mise exec chezmoi -- chezmoi data | jq -r .chezmoi.config.sourceDir)" || fail "could not determine chezmoi dir"
  cmData="${cmDir}/.chezmoidata.toml"
  [ -f $"${cmData}" ] || cat > ${cmData} <<EOF
[chezmoidata]
brewuser = "${BREWUSER}"
gituser = "${USER}"
EOF
  mise exec chezmoi -- chezmoi init apply || fail "could not apply chezmoi"
  mise install
}

[ "${OS}" = "arch" ] && install base-devel
check_install curl
check_install git
check_install jq
check_install zsh
check_install_mise
chsh_zsh
bootstrap_chezmoi
