# Set PATH, MANPATH, etc., for Homebrew. Probe the known prefixes rather than
# hardcoding one: this file is stowed on Linux too (install.linux.sh), and on an
# Intel Mac brew lives under /usr/local. A hardcoded ARM path made every login
# shell on those machines print "no such file or directory".
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [[ -x "$_brew" ]] && { eval "$("$_brew" shellenv)"; break; }
done
unset _brew
