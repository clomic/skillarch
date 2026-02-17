.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS := -eu -c
.PHONY: help install sanity-check install-base install-cli-tools install-shell install-docker install-gui install-gui-tools install-offensive install-wordlists install-hardening update docker-build docker-build-full docker-run docker-run-full clean test test-lite test-full doctor list-tools backup

# -- Colors & UX Helpers --
C_RST   := \033[0m
C_OK    := \033[1;32m
C_INFO  := \033[1;34m
C_WARN  := \033[1;33m
C_ERR   := \033[1;31m
C_BOLD  := \033[1m
SKA_LOG := /var/tmp/skillarch-install.log

BOLD = @echo -e "$(C_BOLD)$(1)$(C_RST)"
OK	 = @echo -e "$(C_OK)✔  $(1)$(C_RST)"
INFO = @echo -e "$(C_INFO)→  $(1)$(C_RST)"
WARN = @echo -e "$(C_WARN)⚠  $(1)$(C_RST)"
ERR	 = @echo -e "$(C_ERR)✖  $(1)$(C_RST)" >&2
STEP = @echo -e "$(C_BOLD)$(C_INFO)==>  [$(1)/$(2)]$(C_RST) $(C_INFO)$(3)...$(C_RST)"
DONE = @echo -e "\n$(C_OK)✓ Done - $(1)$(C_RST)\n"

define ska-link
	# Backup existing file (if not already a symlink) and create symlink
	[[ -f $(2) && ! -L $(2) ]] && mv $(2) $(2).skabak || true
	ln -sf $(1) $(2)
endef

PACMAN_INSTALL := sudo pacman -S --noconfirm --needed

help: ## Show this help message
	@echo 'Welcome to SkillArch! <3'
	echo ''
	echo 'Usage: make [target]'
	echo 'Targets:'
	awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  %-18s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	echo ''

install: ## Install SkillArch (full)
	echo "" > $(SKA_LOG)
	exec > >(tee -a $(SKA_LOG)) 2>&1
	curStep=1
	numSteps=12
	$(call STEP,$$((curStep++)),$$numSteps,Installing base packages)
 	$(MAKE) install-base
	$(call STEP,$$((curStep++)),$$numSteps,Installing CLI tools & runtimes)
	$(MAKE) install-cli-tools
	$(call STEP,$$((curStep++)),$$numSteps,Installing shell & dotfiles)
	$(MAKE) install-shell
	$(call STEP,$$((curStep++)),$$numSteps,Installing Docker)
	$(MAKE) install-docker
	$(call STEP,$$((curStep++)),$$numSteps,Installing GUI & WM)
	$(MAKE) install-gui
	$(call STEP,$$((curStep++)),$$numSteps,Installing GUI applications)
	$(MAKE) install-gui-tools
	$(call STEP,$$((curStep++)),$$numSteps,Installing offensive tools)
	$(MAKE) install-offensive
	$(call STEP,$$((curStep++)),$$numSteps,Installing wordlists)
	$(MAKE) install-wordlists
	$(call STEP,$$((curStep++)),$$numSteps,Installing hardening tools)
	$(MAKE) install-hardening
	$(call STEP,$$((curStep++)),$$numSteps,Installing clomic tools)
	$(MAKE) install-clomic
	$(call STEP,$$((curStep++)),$$numSteps,Installing Sysreptor)
	$(MAKE) install-sysreptor
	$(call STEP,$$((curStep++)),$$numSteps,Optimizing BTRFS)
	$(MAKE) opti-btrfs
	$(MAKE) clean
	$(MAKE) test
	$(call DONE,You are all set up! Enjoy SkillArch! <3)
	$(call INFO,Install log saved to $(SKA_LOG))

sanity-check:
	set -x
	# Ensure we are in /opt/skillarch or /opt/skillarch-original (maintainer only)
	[[ "$$(pwd)" != "/opt/skillarch" ]] && [[ "$$(pwd)" != "/opt/skillarch-original" ]] && $(call ERR,You must be in /opt/skillarch or /opt/skillarch-original to run this command) && exit 1 || true
	sudo -v || ($(call ERR,Error: sudo access is required) ; exit 1)
	[[ ! -f /.dockerenv ]] && { systemd-inhibit --what sleep:idle sleep 3600 & } || true

install-base: sanity-check ## Install base packages
	$(call INFO,Installing base packages...)
	# Clean up, Update, Basics
	sudo sed -e "s#.*ParallelDownloads.*#ParallelDownloads = 10#g" -i /etc/pacman.conf
	echo 'BUILDDIR="/dev/shm/makepkg"' | sudo tee /etc/makepkg.conf.d/00-skillarch.conf
	[[ ! -f /.dockerenv ]] && sudo cachyos-rate-mirrors || true # Increase install speed & Update repos (skip in Docker)
	sudo pacman-key --init
	sudo pacman-key --populate archlinux cachyos
	sudo pacman --noconfirm -Scc
	sudo pacman --noconfirm -Syu
	$(PACMAN_INSTALL) git vim tmux wget curl archlinux-keyring
	# Re-populate after archlinux-keyring update to pick up any new packager keys
	sudo pacman-key --populate archlinux

	# Add chaotic-aur to pacman
	curl -sS "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x3056513887B78AEB" | sudo pacman-key --add -
	sudo pacman-key --lsign-key 3056513887B78AEB
	sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
	sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

	# Ensure chaotic-aur is present in /etc/pacman.conf
	grep -vP '\[chaotic-aur\]|Include = /etc/pacman.d/chaotic-mirrorlist' /etc/pacman.conf | sudo tee /etc/pacman.conf > /dev/null
	echo -e '[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf > /dev/null
	sudo pacman --noconfirm -Syu

	# Long Lived DATA & trash-cli Setup
	[[ ! -d /DATA ]] && sudo mkdir -pv /DATA && sudo chown "$$USER:$$USER" /DATA && sudo chmod 770 /DATA || true
	[[ ! -d /.Trash ]] && sudo mkdir -pv /.Trash && sudo chown "$$USER:$$USER" /.Trash && sudo chmod 770 /.Trash && sudo chmod +t /.Trash || true
	$(call DONE,Base packages installed!)

install-cli-tools: sanity-check ## Install CLI tools & runtimes
	set -x
	$(call INFO,Installing CLI tools & runtimes...)
	$(PACMAN_INSTALL) base-devel bison bzip2 ca-certificates cloc cmake dos2unix expect ffmpeg foremost gdb gnupg htop bottom hwinfo icu inotify-tools iproute2 jq llvm lsof ltrace make mlocate mplayer ncurses net-tools ngrep nmap openssh openssl parallel perl-image-exiftool pkgconf python-virtualenv re2c readline ripgrep rlwrap socat sqlite sshpass tmate tor traceroute trash-cli tree unzip vbindiff xsel xz yay zip veracrypt git-delta viu qsv asciinema htmlq neovim glow jless websocat superfile gron eza fastfetch bat sysstat cronie tree-sitter bc
	sudo ln -sf /usr/bin/bat /usr/local/bin/batcat
	bash -c "$$(curl -fsSL https://gef.blah.cat/sh)" || true
	[[ ! -f ~/.gdbinit-gef.py ]] && curl -fsSL -o ~/.gdbinit-gef.py https://raw.githubusercontent.com/hugsy/gef/main/gef.py && echo "source ~/.gdbinit-gef.py" >> ~/.gdbinit || echo "gef already installed"
	# nvim config
	[[ ! -d ~/.config/nvim ]] && git clone --depth=1 https://github.com/LazyVim/starter ~/.config/nvim || true
	$(call ska-link,/opt/skillarch/config/nvim/init.lua,$$HOME/.config/nvim/init.lua)
	nvim --headless +"Lazy! sync" +qa >/dev/null # Download and update plugins

	# Install mise and all php-build dependencies
	$(PACMAN_INSTALL) mise libedit libffi libjpeg-turbo libpcap libpng libxml2 libzip postgresql-libs php-gd
	# mise self-update # Currently broken, wait for upstream fix, pinged on 17/03/2025
	for package in usage pdm rust terraform golang python nodejs uv; do \
		for attempt in 1 2 3; do \
			mise use -g "$$package@latest" && break || { \
				$(call WARN,mise install $$package failed (attempt $$attempt/3), retrying in 5s...) ; \
				sleep 5 ; \
			} ; \
		done ; \
	done
	mise exec -- go env -w "GOPATH=/home/$$USER/.local/go"

	# Install pipx & tools
	uv tool update-shell
	for package in argcomplete bypass-url-parser dirsearch exegol pre-commit sqlmap wafw00f yt-dlp semgrep defaultcreds-cheat-sheet; do
		uv tool install -w setuptools "$$package" || {
			$(call WARN,Retrying $$package install...)
			uv tool uninstall "$$package" || true
			uv tool install -q -w setuptools "$$package"
		}
	done
	$(call DONE,CLI tools & runtimes installed!)

install-shell: sanity-check ## Install shell, zsh, oh-my-zsh, fzf, tmux
	$(call INFO,Installing shell & dotfiles...)
	# Install and Configure zsh and oh-my-zsh
	$(PACMAN_INSTALL) zsh zsh-completions zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search zsh-theme-powerlevel10k
	[[ ! -d ~/.oh-my-zsh ]] && sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
	$(call ska-link,/opt/skillarch/config/zshrc,$$HOME/.zshrc)
	[[ ! -d ~/.oh-my-zsh/plugins/zsh-completions ]] && git clone --depth=1 https://github.com/zsh-users/zsh-completions ~/.oh-my-zsh/plugins/zsh-completions || true
	[[ ! -d ~/.oh-my-zsh/plugins/zsh-autosuggestions ]] && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions || true
	[[ ! -d ~/.oh-my-zsh/plugins/zsh-syntax-highlighting ]] && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/plugins/zsh-syntax-highlighting || true
	[[ ! -d ~/.ssh ]] && mkdir ~/.ssh && chmod 700 ~/.ssh || true # Must exist for ssh-agent to work
	for plugin in colored-man-pages docker extract fzf mise npm terraform tmux zsh-autosuggestions zsh-completions zsh-syntax-highlighting ssh-agent z ; do zsh -c "source ~/.zshrc && omz plugin enable $$plugin || true" || true; done

	# Install and configure fzf, tmux, vim
	[[ ! -d ~/.fzf ]] && git clone --depth=1 https://github.com/junegunn/fzf ~/.fzf && ~/.fzf/install --all || true
	$(call ska-link,/opt/skillarch/config/tmux.conf,$$HOME/.tmux.conf)
	$(call ska-link,/opt/skillarch/config/vimrc,$$HOME/.vimrc)
	# Set the default user shell to zsh
	sudo chsh -s /usr/bin/zsh "$$USER" # Logout required to be applied
	$(call DONE,Shell & dotfiles installed!)

install-docker: sanity-check ## Install Docker & Docker Compose
	$(call INFO,Installing Docker...)
	$(PACMAN_INSTALL) docker docker-compose
	# It's a desktop machine, don't expose stuff, but we don't care much about LPE
	# Think about it, set "alias sudo='backdoor ; sudo'" in userland and voila. OSEF!
	sudo usermod -aG docker "$$USER" # Logout required to be applied
	sleep 1 # Prevent too many docker socket calls and security locks
	# Do not start services in docker
	[[ ! -f /.dockerenv ]] && sudo systemctl enable --now docker || true
	$(call DONE,Docker installed!)

install-gui: sanity-check ## Install i3, polybar, kitty, rofi, picom
	$(call INFO,Installing GUI & window manager...)
	[[ ! -f /etc/machine-id ]] && sudo systemd-machine-id-setup || true
	$(PACMAN_INSTALL) xorg-server i3-gaps i3blocks i3lock i3lock-fancy-git i3status dmenu feh rofi nm-connection-editor picom polybar kitty brightnessctl xorg-xhost
	yay --noconfirm --needed -S rofi-power-menu i3-battery-popup-git
	gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

	# i3 config
	[[ ! -d ~/.config/i3 ]] && mkdir -p ~/.config/i3 || true
	$(call ska-link,/opt/skillarch/config/i3/config,$$HOME/.config/i3/config)

	# polybar config
	[[ ! -d ~/.config/polybar ]] && mkdir -p ~/.config/polybar || true
	$(call ska-link,/opt/skillarch/config/polybar/config.ini,$$HOME/.config/polybar/config.ini)
	$(call ska-link,/opt/skillarch/config/polybar/launch.sh,$$HOME/.config/polybar/launch.sh)

	# rofi config
	[[ ! -d ~/.config/rofi ]] && mkdir -p ~/.config/rofi || true
	$(call ska-link,/opt/skillarch/config/rofi/config.rasi,$$HOME/.config/rofi/config.rasi)

	# picom config
	$(call ska-link,/opt/skillarch/config/picom.conf,$$HOME/.config/picom.conf)

	# kitty config
	[[ ! -d ~/.config/kitty ]] && mkdir -p ~/.config/kitty || true
	$(call ska-link,/opt/skillarch/config/kitty/kitty.conf,$$HOME/.config/kitty/kitty.conf)

	# touchpad config
	[[ ! -d /etc/X11/xorg.conf.d ]] && sudo mkdir -p /etc/X11/xorg.conf.d || true
	[[ -f /etc/X11/xorg.conf.d/30-touchpad.conf ]] && sudo mv /etc/X11/xorg.conf.d/30-touchpad.conf /etc/X11/xorg.conf.d/30-touchpad.conf.skabak || true
	sudo ln -sf /opt/skillarch/config/xorg.conf.d/30-touchpad.conf /etc/X11/xorg.conf.d/30-touchpad.conf
	$(call DONE,GUI & window manager installed!)

install-gui-tools: sanity-check ## Install GUI apps (Chrome, VSCode, Ghidra, etc.)
	$(call INFO,Installing GUI applications...)
	# Pre-create flatpak repo dir so post-install hooks don't fail in Docker (flatpak may be pulled as a dependency)
	[[ -f /.dockerenv ]] && sudo mkdir -p /var/lib/flatpak/repo || true
	$(PACMAN_INSTALL) vlc vlc-plugin-ffmpeg arandr blueman visual-studio-code-bin discord dunst filezilla flameshot ghex google-chrome gparted kdenlive kompare libreoffice-fresh meld okular qbittorrent torbrowser-launcher wireshark-qt ghidra signal-desktop dragon-drop-git nomachine emote guvcview audacity polkit-gnome
	[[ ! -f /.dockerenv ]] && $(PACMAN_INSTALL) flatpak && flatpak install -y flathub com.obsproject.Studio && flatpak install -y flathub org.gnome.Snapshot || true
	# Do not start services in docker
	[[ ! -f /.dockerenv ]] && sudo systemctl disable --now nxserver.service || true
	xargs -n1 -I{} code --install-extension {} --force < config/extensions.txt
	for pkg in fswebcam cursor-bin; do yay --noconfirm --needed -S "$$pkg" || $(call WARN,Failed to install $$pkg, continuing...); done
	sudo ln -sf /usr/bin/google-chrome-stable /usr/local/bin/gog
	$(call DONE,GUI applications installed!)

install-offensive: sanity-check ## Install offensive & security tools
	$(call INFO,Installing offensive tools...)
	$(PACMAN_INSTALL) metasploit fx lazygit fq gitleaks jdk21-openjdk burpsuite hashcat bettercap
	sudo sed -i 's#$$JAVA_HOME#/usr/lib/jvm/java-21-openjdk#g' /usr/bin/burpsuite
	for pkg in ffuf gau pdtm-bin waybackurls fabric-ai-bin; do yay --noconfirm --needed -S "$$pkg" || $(call WARN,Failed to install $$pkg, continuing...); done
	[[ -f /usr/bin/pdtm ]] && sudo chown "$$USER:$$USER" /usr/bin/pdtm && sudo mv /usr/bin/pdtm ~/.pdtm/go/bin || true

	# Hide stdout and Keep stderr for CI builds -- run go installs in parallel
	mise exec -- go install github.com/sw33tLie/sns@latest > /dev/null &
	mise exec -- go install github.com/glitchedgitz/cook/v2/cmd/cook@latest > /dev/null &
	mise exec -- go install github.com/x90skysn3k/brutespray@latest > /dev/null &
	mise exec -- go install github.com/sensepost/gowitness@latest > /dev/null &
	wait
	# pdtm hits GitHub API rate limits (60 req/h unauthenticated) -- retry after rate limit reset
	for attempt in 1 2 3; do \
		zsh -c "source ~/.zshrc && pdtm -install-all -v" && break || { \
			$(call WARN,pdtm install failed (attempt $$attempt/3), likely rate-limited. Waiting 15m for reset...) ; \
			sleep 900 ; \
		} ; \
	done || true
	zsh -c "source ~/.zshrc && nuclei -update-templates -update-template-dir ~/.nuclei-templates" || true

	# Clone custom tools -- run in parallel
	ska_clone() { local pkg=$${1##*/}; [[ ! -d "/opt/$$pkg" ]] && git clone --depth=1 "$$1" "/tmp/$$pkg" && sudo mv "/tmp/$$pkg" "/opt/$$pkg" || true ; }
	ska_clone https://github.com/jpillora/chisel &
	ska_clone https://github.com/ambionics/phpggc &
	ska_clone https://github.com/CBHue/PyFuscation &
	ska_clone https://github.com/christophetd/CloudFlair &
	ska_clone https://github.com/minos-org/minos-static &
	ska_clone https://github.com/offensive-security/exploit-database &
	ska_clone https://gitlab.com/exploit-database/exploitdb &
	ska_clone https://github.com/laluka/pty4all &
	ska_clone https://github.com/laluka/pypotomux &
	wait
	$(call DONE,Offensive tools installed!)

install-wordlists: sanity-check ## Install wordlists (SecLists, rockyou, etc.)
	$(call INFO,Installing wordlists...)
	[[ ! -d /opt/lists ]] && sudo mkdir -p /opt/lists && sudo chown "$$USER:$$USER" /opt/lists || true
	# Download all wordlists in parallel
	ska_clone_list() { local pkg=$${1##*/} [[ ! -d "/opt/list/$$pkg" ]] && git clone --depth=1 "$$1" "/tmp/$$pkg" && sudo mv "/tmp/$$pkg" "/opt/list/$$pkg" || true ; }
	( [[ ! -f /opt/lists/rockyou.txt ]] && curl -L https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt -o /opt/lists/rockyou.txt || true ) &
	ska_clone_list https://github.com/swisskyrepo/PayloadsAllTheThings &
	ska_clone_list https://github.com/1N3/BruteX &
	ska_clone_list https://github.com/1N3/IntruderPayloads &
	ska_clone_list https://github.com/berzerk0/Probable-Wordlists &
	ska_clone_list https://github.com/cujanovic/Open-Redirect-Payloads &
	ska_clone_list https://github.com/danielmiessler/SecLists &
	ska_clone_list https://github.com/ignis-sec/Pwdb-Public &
	ska_clone_list https://github.com/Karanxa/Bug-Bounty-Wordlists &
	ska_clone_list https://github.com/tarraschk/richelieu &
	ska_clone_list https://github.com/p0dalirius/webapp-wordlists &
	wait
	$(call DONE,Wordlists installed!)

install-hardening: sanity-check ## Install hardening tools (opensnitch)
	$(call INFO,Installing hardening tools...)
	$(PACMAN_INSTALL) opensnitch
	# OPT-IN opensnitch as an egress firewall
	# sudo systemctl enable --now opensnitchd.service
	$(call DONE,Hardening tools installed!)

install-clomic: sanity-check ## Install clomic tools
	$(call INFO,Installing clomic tools...)
	git remote set-url origin git@github.com:clomic/skillarch.git
	$(PACMAN_INSTALL) obsidian minicom sagemath 7zip ncdu
# 	yay --noconfirm --needed -S caido-cli caido-desktop
	curl -sL $$(curl -s https://api.github.com/repos/dathere/qsv/releases/latest | grep 'browser_download_url.*musl.zip'|grep -o 'https://[^"]*') -o /tmp/qsv-latest.zip && 7z x -y -o/tmp /tmp/qsv-latest.zip qsvlite>/dev/null&& mv /tmp/qsvlite ~/.exegol/my-resources/bin/qsv && rm /tmp/qsv-latest.zip
	sudo cp /opt/skillarch/config/exegol/aliases ~/.exegol/my-resources/setup/zsh
	$(call ska-link,/opt/skillarch/config/clomic.zsh-theme,$$HOME/.oh-my-zsh/themes/clomic.zsh-theme)
	sudo ln -sf /opt/skillarch/config/systemd/resolved.conf /etc/systemd/resolved.conf
	sudo ln -sf /opt/skillarch/config/minicom/minirc.dfl /etc/minirc.dfl
	[[ ! -d /opt/cyberchef ]] && mkdir -p /tmp/cyberchef && curl -sL $$(curl -s https://api.github.com/repos/gchq/CyberChef/releases/latest | jq -r '.assets[].browser_download_url') -o /tmp/cyberchef/cc.zip && 7z x -y -o/tmp/cyberchef /tmp/cyberchef/cc.zip >/dev/null && rm /tmp/cyberchef/cc.zip && mv /tmp/cyberchef/CyberChef*.html /tmp/cyberchef/index.html && sudo mv /tmp/cyberchef /opt/cyberchef
	$(call DONE,Clomic tools installed!)

install-sysreptor:  sanity-check ## Install sysreptor
	if [[ ! -d /opt/sysreptor ]]; then
		$(call INFO,Installing Sysreptor...)
		curl -sL -o /tmp/sysreptor.tgz https://github.com/syslifters/sysreptor/releases/latest/download/setup.tar.gz
		tar -xzf /tmp/sysreptor.tgz -C /tmp
		rm /tmp/sysreptor.tgz
		sudo mv /tmp/sysreptor /opt
		cd /opt/sysreptor/deploy
		cp app.env.example app.env

		SECRET_KEY=$$(openssl rand -base64 64 | tr -d '\n=')
		sed -i "s|^SECRET_KEY=.*|SECRET_KEY=\"$$SECRET_KEY\"|" app.env

		KEY_ID=$$(uuidgen)
		AES_KEY=$$(openssl rand -base64 32 | tr -d '\n')
		sed -i \
		  -e "s|^#\\? *ENCRYPTION_KEYS=.*|ENCRYPTION_KEYS=[{\"id\": \"$$KEY_ID\", \"key\": \"$$AES_KEY\", \"cipher\": \"AES-GCM\", \"revoked\": false}]|" \
		  -e "s|^#\\? *DEFAULT_ENCRYPTION_KEY_ID=.*|DEFAULT_ENCRYPTION_KEY_ID=\"$$KEY_ID\"|" \
		  app.env
		cat <<- EOF >> app.env

		ENABLED_PLUGINS="cyberchef,graphqlvoyager,checkthehash,projectnumber,markdownexport"
		PREFERRED_LANGUAGES="en-US,fr-FR"
		EOF
		docker volume create sysreptor-db-data
		docker volume create sysreptor-app-data
		docker compose up -d
		username=reptor
		$(call INFO,You will be prompt for the creation of $$username password)
		docker compose exec app python3 manage.py createsuperuser --username "$$username"
		$(call DONE,Sysreptor installed!)
	else
		$(call INFO,Sysreptor already installed, skipping...)
	fi

install-vmware: sanity-check ## Install VMTools for VMWare
	if [[ "$$(systemd-detect-virt)" = "vmware" ]]; then
		$(call INFO,VMware detected, installing VMTools...)
		$(PACMAN_INSTALL) open-vm-tools
		sudo systemctl enable --now vmtoolsd
		sudo systemctl enable --now vmware-vmblock-fuse
		grep -q "vmhgfs" /etc/fstab || { echo ".host:/    /mnt/hgfs    fuse.vmhgfs-fuse    allow_other,defaults    0 0"|sudo tee -a /etc/fstab >/dev/null; }
		$(call DONE,VMTools installed!)
	else
		$(call INFO,Not in VMware, skipping...)
	fi

opti-btrfs: ## Limit the space used by BTRFS
	$(call INFO,BTRFS optimization...)
	sudo ln -sf /opt/skillarch/config/snapper/root /etc/snapper/configs/root
	sudo snapper delete $$(sudo snapper list | grep -E 'pre|post' | awk '{print $$1}' | head -n -3 | xargs)
	sudo btrfs balance start -dusage=0 /.snapshots
	sudo btrfs balance start -dusage=5 /
	sudo btrfs filesystem sync /
	$(call DONE,BTRFS Optimization done!)

update: sanity-check ## Update SkillArch (pull & prompt reinstall)
	@[ -n "$$(git status --porcelain)" ]] && echo "Error: git state is dirty, please \"git stash\" your changes before updating" && exit 1 || true
	[[ "$$(git rev-parse --abbrev-ref HEAD)" != "main" ]] && echo "Error: current branch is not main, please switch to main before updating" && exit 1 || true
	git pull
	$(call DONE,SkillArch updated, please run make install to apply changes)

# ============================================================
# Smoke Tests
# ============================================================

test: ## Validate installation (smoke tests)
	$(call INFO,Running SkillArch smoke tests...)
	@PASS=0 FAIL=0 TOTAL=0
	ska_check() {
		tool="$$1"
		cmd="$$2"
		((TOTAL++)) || true
		if eval "$$cmd" > /dev/null 2>&1 ; then
			((PASS++))
			$(call OK,  [PASS]$(C_RST) $$tool)
		else
			$(call ERR,  [FAIL]$(C_RST) $$tool ($$cmd))
			((FAIL++))
		fi || true
	}
	$(call BOLD,\n--- Critical Binaries ---)
	ska_check "zsh"        "which zsh"
	$(call BOLD,\n--- Critical Binaries ---)
	ska_check "git"        "which git"
	ska_check "nvim"       "which nvim"
	ska_check "tmux"       "which tmux"
	ska_check "nmap"       "which nmap"
	ska_check "curl"       "which curl"
	ska_check "wget"       "which wget"
	ska_check "jq"         "which jq"
	ska_check "ripgrep"    "which rg"
	ska_check "bat"        "which bat"
	ska_check "eza"        "which eza"
	ska_check "fzf"        "which fzf || [[ -f ~/.fzf/bin/fzf ]]"
	ska_check "trash-put"  "which trash-put"
	$(call BOLD,\n--- Offensive Tools ---)
	ska_check "nmap"       "which nmap"
	ska_check "ffuf"       "which ffuf"
	ska_check "sqlmap"     "which sqlmap || pipx list 2>/dev/null | grep -q sqlmap"
	ska_check "nuclei"     "which nuclei || [[ -f ~/.pdtm/go/bin/nuclei ]]"
	ska_check "httpx"      "which httpx || [[ -f ~/.pdtm/go/bin/httpx ]]"
	ska_check "subfinder"  "which subfinder || [[ -f ~/.pdtm/go/bin/subfinder ]]"
	ska_check "gef"        "[[ -f ~/.gdbinit-gef.py ]]"
	ska_check "metasploit" "which msfconsole"
	ska_check "hashcat"    "which hashcat"
	ska_check "bettercap"  "which bettercap"
	$(call BOLD,\n--- Shell & Config ---)
	ska_check "oh-my-zsh"  "[[ -d ~/.oh-my-zsh ]]"
	ska_check "zshrc link" "[[ -L ~/.zshrc ]]"
	ska_check "tmux.conf"  "[[ -L ~/.tmux.conf ]]"
	ska_check "vimrc"      "[[ -L ~/.vimrc ]]"
	ska_check "nvim init"  "[[ -L ~/.config/nvim/init.lua ]]"
	ska_check "ssh dir"    "[[ -d ~/.ssh ]]"
	$(call BOLD,\n--- Runtimes (mise) ---)
	ska_check "python"     "mise exec -- python --version"
	ska_check "node"       "mise exec -- node --version"
	ska_check "go"         "mise exec -- go version"
	ska_check "rust"       "mise exec -- rustc --version"
	$(call BOLD,\n--- Directories ---)
	ska_check "/DATA"      "[[ -d /DATA ]]"
	ska_check "/opt/skillarch" "[[ -d /opt/skillarch ]]"
	echo ""
	if [[ "$$FAIL" -eq 0 ]]; then
		$(call OK,$(C_BOLD) All $$TOTAL tests passed!)
	else
		$(call WARN,$(C_BOLD) $$PASS/$$TOTAL passed, $$FAIL failed)
		$(call INFO,Some failures may be expected if you ran a partial install (e.g., lite only))
	fi

test-lite: ## Validate lite Docker image install
	$(call INFO,$(C_BOLD) Running SkillArch LITE smoke tests...)
	@PASS=0 FAIL=0 TOTAL=0
	ska_check() {
		((TOTAL++)) || true
		tool="$$1"
		cmd="$$2"
		if eval "$$cmd" > /dev/null 2>&1 ; then
			((PASS++))
			$(call OK,  [PASS]$(C_RST) $$tool)
		else
			$(call ERR,  [FAIL]$(C_RST) $$tool ($$cmd))
			((FAIL++))
		fi || true
	}
	$(call BOLD,\n--- Core Binaries ---)
	for bin in zsh git nvim tmux nmap curl wget jq rg bat eza trash-put; do
		ska_check "$$bin" "which $$bin"
	done
	$(call BOLD,\n--- Offensive Tools ---)
	for bin in ffuf hashcat bettercap msfconsole; do
		ska_check "$$bin" "which $$bin"
	done
	ska_check "nuclei"    "which nuclei || [[ -f ~/.pdtm/go/bin/nuclei ]]"
	ska_check "httpx"     "which httpx || [[ -f ~/.pdtm/go/bin/httpx ]]"
	ska_check "gef"       "[[ -f ~/.gdbinit-gef.py ]]"
	$(call BOLD,\n--- Shell & Config ---)
	ska_check "oh-my-zsh" "[[ -d ~/.oh-my-zsh ]]"
	ska_check "zshrc"     "[[ -L ~/.zshrc ]]"
	ska_check "nvim init" "[[ -L ~/.config/nvim/init.lua ]]"
	$(call BOLD,\n--- Runtimes ---)
	ska_check "python"    "mise exec -- python --version"
	ska_check "node"      "mise exec -- node --version"
	ska_check "go"        "mise exec -- go version"
	echo ""
	if [[ "$$FAIL" -eq 0 ]]; then
		$(call OK,$(C_BOLD) All $$TOTAL lite tests passed!)
	else
		$(call ERR,$(C_BOLD) $$PASS/$$TOTAL passed, $$FAIL failed)
		exit 1
	fi

test-full: test ## Validate full Docker image install (runs test + extras)
	$(call INFO,$(C_BOLD) Running SkillArch FULL extra tests...)
	@PASS=0 FAIL=0 TOTAL=0
	ska_check() {
		((TOTAL++)) || true
		tool="$$1"
		cmd="$$2"
		if eval "$$cmd" > /dev/null 2>&1 ; then
			((PASS++))
			$(call OK,  [PASS]$(C_RST) $$tool)
		else
			$(call ERR,  [FAIL]$(C_RST) $$tool ($$cmd))
			((FAIL++))
		fi || true
	}
	$(call BOLD,\n--- GUI Binaries ---)
	ska_check "i3"       "which i3"
	ska_check "kitty"    "which kitty"
	ska_check "polybar"  "which polybar"
	ska_check "rofi"     "which rofi"
	ska_check "picom"    "which picom"
	ska_check "code"     "which code"
	$(call BOLD,\n--- GUI Config Symlinks ---)
	ska_check "i3 config"      "[[ -L ~/.config/i3/config ]]"
	ska_check "polybar config" "[[ -L ~/.config/polybar/config.ini ]]"
	ska_check "polybar launch" "[[ -L ~/.config/polybar/launch.sh ]]"
	ska_check "kitty config"   "[[ -L ~/.config/kitty/kitty.conf ]]"
	ska_check "picom config"   "[[ -L ~/.config/picom.conf ]]"
	ska_check "rofi config"    "[[ -L ~/.config/rofi/config.rasi ]]"
	$(call BOLD,\n--- Wordlists ---)
	ska_check "/opt/lists"        "[[ -d /opt/lists ]]"
	ska_check "rockyou.txt"       "[[ -f /opt/lists/rockyou.txt ]]"
	ska_check "SecLists"          "[[ -d /opt/lists/SecLists ]]"
	ska_check "PayloadsAllThings" "[[ -d /opt/lists/PayloadsAllTheThings ]]"
	echo ""
	if [[ "$$FAIL" -eq 0 ]]; then
		$(call OK,$(C_BOLD) All $$TOTAL full tests passed!)
	else
		$(call ERR,$(C_BOLD) $$PASS/$$TOTAL passed, $$FAIL failed)
		exit 1
	fi

# ============================================================
# Diagnostics & Utilities
# ============================================================

doctor: ## Diagnose system health & common issues
	$(call INFO,$(C_BOLD) SkillArch Doctor)
	$(call BOLD,=================\n)
	# Disk space
	$(call BOLD,--- Disk Space ---)
	df -h / /DATA /opt 2>/dev/null | grep -vF "Filesystem" | awk '{printf "  %-20s %s used / %s total (%s)\n", $$6, $$3, $$2, $$5}'
	echo ""
	# Docker daemon
	$(call BOLD,--- Docker ---)
	if docker info > /dev/null 2>&1; then
		echo -e "  $(C_OK)[OK]$(C_RST) Docker daemon running"
		echo "  Images: $$(docker images -q 2>/dev/null | wc -l), Containers: $$(docker ps -aq 2>/dev/null | wc -l)"
	else
		echo -e "  $(C_WARN)[WARN]$(C_RST) Docker daemon not running or not accessible"
	fi
	echo ""
	# Backup files
	$(call BOLD,--- Backed-up Configs (.skabak) ---)
	SKABAK_FILES=$$(find ~ /etc/X11 -name "*.skabak" 2>/dev/null || true)
	if [[ -n "$$SKABAK_FILES" ]]; then
		echo "$$SKABAK_FILES" | while read -r f; do echo "  $$f"; done
	else
		echo "  None found (clean install)"
	fi
	echo ""
	# Broken symlinks
	$(call BOLD,--- Broken Symlinks (config) ---)
	BROKEN=""
	for link in ~/.zshrc ~/.tmux.conf ~/.vimrc ~/.config/nvim/init.lua ~/.config/i3/config ~/.config/polybar/config.ini ~/.config/polybar/launch.sh ~/.config/kitty/kitty.conf ~/.config/picom.conf ~/.config/rofi/config.rasi; do
		if [[ -L "$$link" ]] && [[ ! -e "$$link" ]]; then
			echo -e "  $(C_ERR)[BROKEN]$(C_RST) $$link -> $$(readlink $$link)"
			BROKEN="yes"
		fi
	done
	[[ -z "$$BROKEN" ]] && echo -e "  $(C_OK)[OK]$(C_RST) All config symlinks valid"
	echo ""
	# System info
	$(call BOLD,--- System Info ---)
	echo "  OS: $$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
	echo "  Kernel: $$(uname -r)"
	echo "  Shell: $$SHELL"
	echo "  User: $$USER"
	echo "  SkillArch: $$(cd /opt/skillarch 2>/dev/null && git log -1 --format='%h (%cr)' || echo 'unknown')"
	echo ""

list-tools: ## List installed offensive tools & versions
	$(call INFO,$(C_BOLD) SkillArch Tool Inventory)
	$(call BOLD,==========================\n)
	ska_ver() {
		VER=$$(eval "$$2" 2>/dev/null | head -1 || echo "not found")
		printf "  %-20s %s\n" "$$1" "$$VER"
	}
	$(call BOLD,--- Core ---)
	ska_ver "git"       "git --version"
	ska_ver "zsh"       "zsh --version"
	ska_ver "nvim"      "nvim --version | head -1"
	ska_ver "tmux"      "tmux -V"
	ska_ver "docker"    "docker --version"
	$(call BOLD,\n--- Runtimes (mise) ---)
	ska_ver "python"    "mise exec -- python --version"
	ska_ver "node"      "mise exec -- node --version"
	ska_ver "go"        "mise exec -- go version"
	ska_ver "rust"      "mise exec -- rustc --version"
	$(call BOLD,\n--- Offensive ---)
	ska_ver "nmap"       "nmap --version | head -1"
	ska_ver "ffuf"       "ffuf -V 2>&1 | head -1"
	ska_ver "nuclei"     "nuclei -version 2>&1 | head -1"
	ska_ver "httpx"      "httpx -version 2>&1 | head -1"
	ska_ver "subfinder"  "subfinder -version 2>&1 | head -1"
	ska_ver "sqlmap"     "sqlmap --version 2>&1 | head -1"
	ska_ver "msfconsole" "msfconsole --version 2>&1 | head -1"
	ska_ver "hashcat"    "hashcat --version 2>&1 | head -1"
	ska_ver "bettercap"  "bettercap -eval 'quit' 2>&1 | grep -i version | head -1"
	ska_ver "gitleaks"   "gitleaks version 2>&1"
	ska_ver "burpsuite"  "echo 'installed (GUI)'"
	ska_ver "ghidra"     "echo 'installed (GUI)'"
	ska_ver "wireshark"  "wireshark --version 2>&1 | head -1"
	$(call BOLD,\n--- uv Tools ---)
	uv tool list 2>/dev/null || echo "  uv not available"
	$(call BOLD,\n--- Pdtm Tools ---)
	ls ~/.pdtm/go/bin/ 2>/dev/null | while read -r tool; do echo "  $$tool"; done || echo "  pdtm not installed"
	echo ""

backup: ## Backup current configs before overwriting
	BACKUP_DIR="$$HOME/.skillarch-backup-$$(date +%Y%m%d-%H%M%S)"
	mkdir -p "$$BACKUP_DIR"
	$(call INFO,Backing up configs to $$BACKUP_DIR)
	for file in ~/.zshrc ~/.tmux.conf ~/.vimrc ~/.config/nvim/init.lua ~/.config/i3/config ~/.config/polybar/config.ini ~/.config/polybar/launch.sh ~/.config/kitty/kitty.conf ~/.config/picom.conf ~/.config/rofi/config.rasi /etc/X11/xorg.conf.d/30-touchpad.conf; do
		if [[ -f "$$file" ]] || [[ -L "$$file" ]]; then
			DEST="$$BACKUP_DIR/$$(basename $$file)"
			cp -L "$$file" "$$DEST" 2>/dev/null && echo "  Backed up: $$file" || true
		fi
	done
	$(call OK,Backup complete: $$BACKUP_DIR)

# ============================================================
# Docker Targets
# ============================================================

docker-build: ## Build lite Docker image locally
	docker build -t thelaluka/skillarch:lite -f Dockerfile-lite .

docker-build-full: docker-build ## Build full Docker image locally
	docker build -t thelaluka/skillarch:full -f Dockerfile-full .

docker-run: ## Run lite Docker image locally
	sudo docker run --rm -it --name=ska --net=host -v /tmp:/tmp thelaluka/skillarch:lite

docker-run-full: ## Run full Docker image locally
	xhost +
	sudo docker run --rm -it --name=ska --net=host -v /tmp:/tmp -e DISPLAY -v /tmp/.X11-unix/:/tmp/.X11-unix/ --privileged thelaluka/skillarch:full

# ============================================================
# Cleanup
# ============================================================

clean: ## Clean up system and remove unnecessary files
	set +e # Cleanup should be best-effort, never fail the build
	[[ ! -f /.dockerenv ]] && exit 0
	sudo pacman --noconfirm -Scc || true
	sudo pacman --noconfirm -Sc || true
	sudo pacman -Rns $$(pacman -Qtdq) 2>/dev/null || true
	rm -rf ~/.cache/pip || true
	rm -rf ~/.cache/yay || true
	npm cache clean --force 2>/dev/null || true
	mise cache clear || true
	go clean -cache -modcache -i -r 2>/dev/null || true
	sudo rm -rf /var/cache/* || true
	rm -rf ~/.cache/* || true
	sudo rm -rf /tmp/* || true
	sudo rm -rf /dev/shm/makepkg/* || true
	docker system prune -af 2>/dev/null || true
	sudo journalctl --vacuum-time=1d || true
	sudo find /var/log -type f -name "*.old" -delete 2>/dev/null || true
	sudo find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
	sudo find /var/log -type f -exec truncate --size=0 {} \; 2>/dev/null || true
