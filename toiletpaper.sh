#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() {
    printf "${CYAN}[INFO]${NC} %s\n" "$*"
}

log_step() {
    printf "\n${BLUE}${BOLD}==>${NC} ${WHITE}${BOLD}%s${NC}\n" "$*"
}

log_success() {
    printf "${GREEN}${BOLD}[SUCCESS]${NC} %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}${BOLD}[WARNING]${NC} %s\n" "$*"
}

log_error() {
    printf "${RED}${BOLD}[ERROR]${NC} %s\n" "$*" >&2
}

check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_error "ToiletPaper must be executed with root privileges."
        printf "Please run again using: ${BOLD}sudo %s${NC}\n" "$0"
        exit 1
    fi
}

check_environment() {
    if [[ ! -f /etc/arch-release ]] && [[ ! -f /etc/cachyos-release ]] && ! grep -qi "arch\|cachy" /etc/os-release 2>/dev/null; then
        log_warn "This system does not appear to be Arch Linux or CachyOS."
        read -rp "Do you wish to proceed anyway? [y/N]: " confirm_env < /dev/tty
        if [[ ! "${confirm_env,,}" =~ ^y(es)?$ ]]; then
            log_info "Aborting execution."
            exit 0
        fi
    fi
}

get_target_users() {
    local users=()
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        users+=("${SUDO_USER}")
    else
        while IFS=: read -r uname _ uid _ _ homedir _; do
            if [[ "${uid}" -ge 1000 ]] && [[ "${uid}" -lt 65534 ]] && [[ -d "${homedir}" ]] && [[ "${homedir}" == /home/* ]]; then
                users+=("${uname}")
            fi
        done < /etc/passwd
    fi
    echo "${users[@]}"
}

print_banner() {
    printf "${CYAN}${BOLD}"
    cat << "EOF"
 _____     _ _      _   ____                       
|_   _|__ (_) | ___| |_|  _ \ __ _ _ __   ___ _ __ 
  | |/ _ \| | |/ _ \ __| |_) / _` | '_ \ / _ \ '__|
  | | (_) | | |  __/ |_|  __/ (_| | |_) |  __/ |   
  |_|\___/|_|_|\___|\__|_|   \__,_| .__/ \___|_|   
                                  |_|              
EOF
    printf "${NC}"
    printf "${DIM}  Cleanse CachyOS and return to pristine Vanilla Arch Linux${NC}\n"
    printf "${DIM}  Version: 1.1.0 | Pure Bash Architecture | Zero Dependencies${NC}\n\n"
}

module_pacman_reversion() {
    log_step "Module 1: Pacman & Repository Reversion"

    local tmp_dir
    tmp_dir="$(mktemp -d -t toiletpaper-repo-XXXXXX)"
    log_info "Working directory: ${tmp_dir}"

    pushd "${tmp_dir}" >/dev/null

    log_info "Fetching official CachyOS repository removal bundle..."
    if ! curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz; then
        log_error "Failed to download cachyos-repo.tar.xz from mirror.cachyos.org"
        popd >/dev/null
        rm -rf "${tmp_dir}"
        return 1
    fi

    log_info "Extracting repository removal bundle..."
    tar -xvf cachyos-repo.tar.xz >/dev/null

    if [[ -d cachyos-repo ]]; then
        cd cachyos-repo
        log_info "Executing CachyOS repository removal..."
        if [[ -f ./cachyos-repo.sh ]]; then
            chmod +x ./cachyos-repo.sh
            ./cachyos-repo.sh --remove || log_warn "CachyOS repo removal script completed with warnings."
        else
            log_warn "cachyos-repo.sh not found inside archive."
        fi
        cd ..
    fi

    popd >/dev/null
    log_info "Cleaning up temporary repository installer files..."
    rm -rf "${tmp_dir}"

    log_info "Reinstalling vanilla Arch core/pacman package..."
    pacman -Sy --noconfirm core/pacman

    log_info "Scrubbing '%INSTALLED_DB%' metadata from pacman local database (/var/lib/pacman/local/*/desc)..."
    if [[ -d /var/lib/pacman/local ]]; then
        find /var/lib/pacman/local/ -maxdepth 2 -name desc -type f -exec sed -i '/%INSTALLED_DB%/{N;d;}' {} +
        log_success "Pacman local database cleaned of custom CachyOS fields."
    else
        log_warn "/var/lib/pacman/local not found. Skipping desc scrub."
    fi

    log_success "Module 1 completed: Pacman and repositories successfully reverted to Arch Linux defaults."
}

module_package_resync() {
    log_step "Module 2: Architecture & Package Resync"

    log_info "Clearing local Pacman package cache..."
    pacman -Scc --noconfirm || true

    log_info "Refreshing package databases..."
    pacman -Syy

    log_info "Enumerating native packages to reinstall from official Arch mirrors..."
    local native_pkgs
    native_pkgs="$(pacman -Qqn || true)"

    if [[ -z "${native_pkgs}" ]]; then
        log_warn "No native packages detected for reinstallation."
    else
        local pkg_count
        pkg_count="$(echo "${native_pkgs}" | wc -l)"
        log_info "Force-reinstalling ${pkg_count} packages to replace x86-64-v3/v4 binaries with vanilla x86-64..."
        echo "${native_pkgs}" | pacman -Syu - --noconfirm
    fi

    log_success "Module 2 completed: Package ecosystem synchronized to standard Arch Linux architecture."
}

module_kernel_bootloader() {
    log_step "Module 3: Kernel & Bootloader Swap"

    log_info "Installing standard Arch Linux kernel stack (linux, linux-headers, linux-firmware)..."
    pacman -S --needed --noconfirm linux linux-headers linux-firmware

    log_info "Checking for installed CachyOS kernels and related headers..."
    local cachy_kernels
    cachy_kernels=$(pacman -Qq | grep -E '^linux-cachyos' || true)

    if [[ -n "${cachy_kernels}" ]]; then
        log_info "Found CachyOS kernel packages:\n${cachy_kernels}"
        log_info "Removing CachyOS kernel packages..."
        pacman -Rns --noconfirm ${cachy_kernels} || pacman -Rdd --noconfirm ${cachy_kernels}
        log_success "CachyOS kernels successfully removed."
    else
        log_info "No CachyOS kernels found installed."
    fi

    log_info "Regenerating initramfs images (mkinitcpio)..."
    if command -v mkinitcpio >/dev/null 2>&1; then
        mkinitcpio -P
    fi

    log_info "Detecting and updating bootloader configuration..."
    local bootloader_updated=0

    if [[ -f /boot/grub/grub.cfg ]] || command -v grub-mkconfig >/dev/null 2>&1; then
        log_info "Detected GRUB bootloader. Generating updated grub.cfg..."
        grub-mkconfig -o /boot/grub/grub.cfg
        bootloader_updated=1
    fi

    if [[ -d /boot/loader ]] || (command -v bootctl >/dev/null 2>&1 && bootctl is-installed >/dev/null 2>&1); then
        log_info "Detected systemd-boot. Updating systemd-boot loader..."
        bootctl update || log_warn "bootctl update returned non-zero status."
        bootloader_updated=1
    fi

    if [[ "${bootloader_updated}" -eq 0 ]]; then
        log_warn "No recognized bootloader configuration (GRUB or systemd-boot) automatically updated."
        log_warn "Please ensure your custom bootloader is configured to boot the 'linux' kernel image."
    else
        log_success "Bootloader configuration updated successfully."
    fi

    log_success "Module 3 completed: Standard Arch kernel stack installed and bootloader refreshed."
}

module_bloat_purge() {
    log_step "Module 4: Bloat & Configuration Purge"

    local target_cachy_pkgs=(
        "cachyos-settings"
        "cachyos-gaming-meta"
        "cachyos-hello"
        "cachyos-kernel-manager"
        "cachy-browser"
        "chwd"
        "cachyos-hooks"
        "cachyos-keyring"
        "cachyos-mirrorlist"
        "cachyos-v3-mirrorlist"
        "cachyos-v4-mirrorlist"
    )

    log_info "Scanning for CachyOS-specific packages..."
    local to_remove=()
    for pkg in "${target_cachy_pkgs[@]}"; do
        if pacman -Qq "${pkg}" >/dev/null 2>&1; then
            to_remove+=("${pkg}")
        fi
    done

    while IFS= read -r extra_pkg; do
        if [[ -n "${extra_pkg}" ]]; then
            local exists=0
            for item in "${to_remove[@]}"; do
                if [[ "${item}" == "${extra_pkg}" ]]; then
                    exists=1
                    break
                fi
            done
            if [[ "${exists}" -eq 0 ]]; then
                to_remove+=("${extra_pkg}")
            fi
        fi
    done < <(pacman -Qq | grep -E '^cachyos-|^cachy-' || true)

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing CachyOS packages and unneeded dependencies: ${to_remove[*]}"
        pacman -Rns --noconfirm "${to_remove[@]}" || {
            log_warn "Standard recursive removal failed; attempting forced removal..."
            pacman -Rdd --noconfirm "${to_remove[@]}"
        }
    else
        log_info "No CachyOS bloat packages detected on the system."
    fi

    log_info "Checking for orphaned packages (pacman -Qtdq)..."
    local orphans
    orphans=$(pacman -Qtdq || true)
    if [[ -n "${orphans}" ]]; then
        log_info "Purging orphan packages: ${orphans}"
        pacman -Rns --noconfirm ${orphans} || true
    else
        log_info "No orphan packages found."
    fi

    log_success "Module 4 completed: CachyOS packages and bloat successfully purged."
}

module_os_identity() {
    log_step "Module 5: OS Identity Restoration"

    log_info "Writing vanilla Arch Linux identification to /etc/os-release..."
    cat << 'EOF' > /etc/os-release
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://gitlab.archlinux.org/groups/archlinux/-/issues"
PRIVACY_POLICY_URL="https://terms.archlinux.org/docs/privacy-policy/"
LOGO=archlinux-logo
EOF

    rm -f /etc/cachyos-release /etc/arch-release
    touch /etc/arch-release

    log_success "Module 5 completed: OS identity restored to Arch Linux."
}

module_kde_plasma_reversion() {
    log_step "Module 6: KDE Plasma Reversion & Default Reset"

    local kde_cachy_pkgs=(
        "cachyos-kde-settings"
        "cachyos-nordic-theme"
        "cachyos-emerald-theme"
        "cachyos-wallpapers"
        "plasma-wayland-session-cachyos"
    )

    local to_remove=()
    for pkg in "${kde_cachy_pkgs[@]}"; do
        if pacman -Qq "${pkg}" >/dev/null 2>&1; then
            to_remove+=("${pkg}")
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing CachyOS KDE packages: ${to_remove[*]}"
        pacman -Rns --noconfirm "${to_remove[@]}" || pacman -Rdd --noconfirm "${to_remove[@]}"
    fi

    local target_users
    read -r -a target_users <<< "$(get_target_users)"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    local plasma_config_files=(
        "plasma-org.kde.plasma.desktop-appletsrc"
        "plasmashellrc"
        "kdeglobals"
        "kwinrc"
        "kscreenlockerrc"
        "plasma-localerc"
        "systemsettingsrc"
        "kcminputrc"
    )

    for user in "${target_users[@]}"; do
        local user_home
        user_home="$(getent passwd "${user}" | cut -d: -f6)"
        if [[ -d "${user_home}/.config" ]]; then
            local backup_dir="${user_home}/.config/kde_cachyos_backup_${timestamp}"
            local backed_up=0

            for cfg in "${plasma_config_files[@]}"; do
                if [[ -f "${user_home}/.config/${cfg}" ]]; then
                    if [[ "${backed_up}" -eq 0 ]]; then
                        mkdir -p "${backup_dir}"
                        backed_up=1
                    fi
                    mv "${user_home}/.config/${cfg}" "${backup_dir}/"
                fi
            done

            for act_file in "${user_home}/.config"/kactivitymanagerd*; do
                if [[ -e "${act_file}" ]]; then
                    if [[ "${backed_up}" -eq 0 ]]; then
                        mkdir -p "${backup_dir}"
                        backed_up=1
                    fi
                    mv "${act_file}" "${backup_dir}/"
                fi
            done

            if [[ "${backed_up}" -eq 1 ]]; then
                chown -R "${user}:$(id -gn "${user}")" "${backup_dir}"
                log_success "Backed up modified KDE Plasma configs for user '${user}' to ${backup_dir}"
                log_info "Default vanilla KDE Breeze theme and taskbar layout will be re-initialized on next login."
            fi
        fi
    done

    log_success "Module 6 completed: KDE Plasma reverted to vanilla default state."
}

module_hyprland_reversion() {
    log_step "Module 7: Hyprland Reversion & Noctalia Removal"

    local hypr_cachy_pkgs=(
        "noctalia"
        "noctalia-qs"
        "cachyos-hyprland-settings"
        "cachyos-hyprland-meta"
        "cachyos-hyprland"
        "hyprland-cachyos"
    )

    local to_remove=()
    for pkg in "${hypr_cachy_pkgs[@]}"; do
        if pacman -Qq "${pkg}" >/dev/null 2>&1; then
            to_remove+=("${pkg}")
        fi
    done

    while IFS= read -r extra_noctalia; do
        if [[ -n "${extra_noctalia}" ]]; then
            local exists=0
            for item in "${to_remove[@]}"; do
                if [[ "${item}" == "${extra_noctalia}" ]]; then
                    exists=1
                    break
                fi
            done
            if [[ "${exists}" -eq 0 ]]; then
                to_remove+=("${extra_noctalia}")
            fi
        fi
    done < <(pacman -Qq | grep -E '^noctalia' || true)

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing Noctalia and CachyOS Hyprland packages: ${to_remove[*]}"
        pacman -Rns --noconfirm "${to_remove[@]}" || pacman -Rdd --noconfirm "${to_remove[@]}"
    else
        log_info "No Noctalia or CachyOS Hyprland packages detected."
    fi

    local target_users
    read -r -a target_users <<< "$(get_target_users)"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    for user in "${target_users[@]}"; do
        local user_home
        user_home="$(getent passwd "${user}" | cut -d: -f6)"
        local hypr_dir="${user_home}/.config/hypr"
        local user_group
        user_group="$(id -gn "${user}")"

        if [[ -d "${hypr_dir}" ]]; then
            local hypr_backup="${user_home}/.config/hypr.cachyos.bak-${timestamp}"
            log_info "Backing up '${hypr_dir}' to '${hypr_backup}'..."
            mv "${hypr_dir}" "${hypr_backup}"
            chown -R "${user}:${user_group}" "${hypr_backup}"

            mkdir -p "${hypr_dir}"
            if [[ -f /usr/share/hyprland/hyprland.conf ]]; then
                log_info "Restoring stock vanilla /usr/share/hyprland/hyprland.conf for user '${user}'..."
                cp /usr/share/hyprland/hyprland.conf "${hypr_dir}/hyprland.conf"
            fi
            chown -R "${user}:${user_group}" "${hypr_dir}"
            log_success "Hyprland configuration for '${user}' reset to vanilla default."
        fi

        for noctalia_dir in "${user_home}/.config/noctalia" "${user_home}/.config/noctalia-qs"; do
            if [[ -d "${noctalia_dir}" ]]; then
                local noctalia_backup="${noctalia_dir}.bak-${timestamp}"
                log_info "Moving '${noctalia_dir}' to '${noctalia_backup}'..."
                mv "${noctalia_dir}" "${noctalia_backup}"
                chown -R "${user}:${user_group}" "${noctalia_backup}"
            fi
        done
    done

    log_success "Module 7 completed: Hyprland configuration reset and Noctalia packages removed."
}

MODULE_TITLES=(
    "Pacman & Repository Reversion (Remove Cachy repos, scrub %INSTALLED_DB%)"
    "Architecture & Package Resync (Downgrade x86-64-v3/v4 to standard x86-64)"
    "Kernel & Bootloader Swap (Install standard linux, remove cachyos kernels)"
    "Bloat & Configuration Purge (Remove cachyos-settings, chwd, cachy-browser)"
    "OS Identity Restoration (Overwrite /etc/os-release with Arch Linux)"
    "KDE Plasma Reset [Optional] (Revert themes, taskbar & applets to vanilla Breeze)"
    "Hyprland Reset & Noctalia Purge [Optional] (Reset ~/.config/hypr, purge noctalia/noctalia-qs)"
)

MODULE_STATES=(1 1 1 1 1 0 0)

detect_desktop_defaults() {
    if pacman -Qq cachyos-kde-settings >/dev/null 2>&1 || pacman -Qq plasma-desktop >/dev/null 2>&1 || [[ -f /usr/bin/plasmashell ]]; then
        MODULE_STATES[5]=1
    fi

    if pacman -Qq noctalia >/dev/null 2>&1 || pacman -Qq noctalia-qs >/dev/null 2>&1 || pacman -Qq cachyos-hyprland-settings >/dev/null 2>&1 || [[ -f /usr/bin/Hyprland ]]; then
        MODULE_STATES[6]=1
    fi
}

show_menu() {
    clear
    print_banner
    printf "${BOLD}Select the reversion modules you wish to execute:${NC}\n\n"

    for i in "${!MODULE_TITLES[@]}"; do
        local idx=$((i + 1))
        local mark=" "
        local color="${DIM}"
        if [[ "${MODULE_STATES[$i]}" -eq 1 ]]; then
            mark="X"
            color="${GREEN}${BOLD}"
        fi
        printf "  ${color}[%s]${NC} ${WHITE}${BOLD}%d)${NC} %s\n" "${mark}" "${idx}" "${MODULE_TITLES[$i]}"
    done

    printf "\n"
    printf "${DIM}----------------------------------------------------------------------${NC}\n"
    printf "  ${BOLD}[1-7]${NC} Toggle module     ${BOLD}[A]${NC} Select All     ${BOLD}[N]${NC} Deselect All\n"
    printf "  ${BOLD}[C/Enter]${NC} Confirm & Run   ${BOLD}[Q]${NC} Quit\n"
    printf "${DIM}----------------------------------------------------------------------${NC}\n"
}

run_interactive_menu() {
    detect_desktop_defaults

    while true; do
        show_menu
        read -rp "Choose an option or enter selection: " user_choice < /dev/tty

        case "${user_choice,,}" in
            1|2|3|4|5|6|7)
                local idx=$((user_choice - 1))
                if [[ "${MODULE_STATES[$idx]}" -eq 1 ]]; then
                    MODULE_STATES[$idx]=0
                else
                    MODULE_STATES[$idx]=1
                fi
                ;;
            a|all)
                for i in "${!MODULE_STATES[@]}"; do
                    MODULE_STATES[$i]=1
                done
                ;;
            n|none)
                for i in "${!MODULE_STATES[@]}"; do
                    MODULE_STATES[$i]=0
                done
                ;;
            c|run|go|"")
                local count_selected=0
                for state in "${MODULE_STATES[@]}"; do
                    if [[ "${state}" -eq 1 ]]; then
                        ((count_selected++))
                    fi
                done

                if [[ "${count_selected}" -eq 0 ]]; then
                    printf "\n${YELLOW}[!] No modules selected. Please select at least one module or press Q to exit.${NC}\n"
                    sleep 2
                    continue
                fi
                break
                ;;
            q|quit|exit)
                printf "\n${YELLOW}Operation cancelled by user. Exiting.${NC}\n"
                exit 0
                ;;
            *)
                printf "\n${RED}Invalid input: '%s'. Press ENTER to continue...${NC}" "${user_choice}"
                read -r < /dev/tty
                ;;
        esac
    done
}

main() {
    check_root
    check_environment

    run_interactive_menu

    clear
    print_banner

    printf "${WHITE}${BOLD}Selected Modules for Execution:${NC}\n"
    for i in "${!MODULE_TITLES[@]}"; do
        local idx=$((i + 1))
        if [[ "${MODULE_STATES[$i]}" -eq 1 ]]; then
            printf "  ${GREEN}*${NC} ${BOLD}Module %d:${NC} %s\n" "${idx}" "${MODULE_TITLES[$i]}"
        fi
    done

    printf "\n${YELLOW}${BOLD}[CAUTION] This script performs foundational changes to your system.${NC}\n"
    read -rp "Are you sure you want to begin the reversion process? [y/N]: " final_confirm < /dev/tty
    if [[ ! "${final_confirm,,}" =~ ^y(es)?$ ]]; then
        log_info "Reversion aborted by user."
        exit 0
    fi

    printf "\n"
    local start_time
    start_time="$(date +%s)"

    if [[ "${MODULE_STATES[0]}" -eq 1 ]]; then
        module_pacman_reversion
    fi

    if [[ "${MODULE_STATES[1]}" -eq 1 ]]; then
        module_package_resync
    fi

    if [[ "${MODULE_STATES[2]}" -eq 1 ]]; then
        module_kernel_bootloader
    fi

    if [[ "${MODULE_STATES[3]}" -eq 1 ]]; then
        module_bloat_purge
    fi

    if [[ "${MODULE_STATES[4]}" -eq 1 ]]; then
        module_os_identity
    fi

    if [[ "${MODULE_STATES[5]}" -eq 1 ]]; then
        module_kde_plasma_reversion
    fi

    if [[ "${MODULE_STATES[6]}" -eq 1 ]]; then
        module_hyprland_reversion
    fi

    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))

    printf "\n${GREEN}${BOLD}======================================================================${NC}\n"
    printf "${GREEN}${BOLD} ToiletPaper Reversion Complete! (Elapsed: %ds)${NC}\n" "${duration}"
    printf "${GREEN}${BOLD}======================================================================${NC}\n"
    printf "${WHITE}Your system has been converted to vanilla Arch Linux.${NC}\n"
    printf "${YELLOW}${BOLD}[RECOMMENDATION]${NC} Please reboot your machine now to boot into the standard Arch Linux kernel and environment:\n"
    printf "  ${BOLD}systemctl reboot${NC}\n\n"
}

main "$@"
