Install sddm and enable it, and install kitty

      sudo pacman -S sddm kitty
      
      systemctl enable sddm

Install nwg-drawer and nwg-look, the keybind SUPER+D is added in config for nwg-drawer
      
      sudo pacman -S nwg-drawer nwg-look

Install hyprpanel and paste the config file content in ~/.config/hyprpanel/config.jsonc, exec-once for hyprpanel is added in config

      paru -S ags-hyprpanel-git
      
      paru -S --needed aylurs-gtk-shell-git wireplumber libgtop bluez bluez-utils btop networkmanager dart-sass wl-clipboard brightnessctl swww python upower pacman-contrib power-profiles-daemon gvfs gtksourceview3 libsoup3 grimblast-git wf-recorder-git hyprpicker matugen-bin python-gpustat hyprsunset-git

Install gnome polkit (authentication agent) and gnome keyring (password store), the exec-once for polkit is added in config, and the autostart for keyring is added in autostart.conf file

      sudo pacman -S polkit-gnome gnome-keyring

Install xdg-desktop-portal-hyprland, the env's are added in config

      sudo pacman -S xdg-desktop-portal-hyprland

Install hypridle, hyprlock, hyprpaper, the config files and exec-once are added

      sudo pacman -S hypridle hyprlock hyprpaper

Install cliphist for clipboard manager, the exec-once are added in config

      sudo pacman -S cliphist

Install sugar-candy theme for sddm and catppuccin, tokyo night gtk themes and tela dracula icon theme and bibata cursor theme(the config is added for bibata-modern-ice cursor)

      paru -S sddm-sugar-candy-git tokyonight-gtk-theme-git catppuccin-gtk-theme-mocha tela-circle-icon-theme-dracula bibata-cursor-theme
      
Apply gtk theme and icon theme from nwg-look (GTK Settings) app

To apply sugar-candy theme on sddm, add below in /etc/sddm.conf.d/sddm.conf file, if the file doesn't exist by default then create one
      
      [General]
      Numlock=on
      
      [Theme]
      Current=sugar-candy

Copy brave-browser.desktop file from /usr/share/applications to ~/.local/share/applications and add the below flags in exec line

      Exec=brave --enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,UseOzonePlatform --ozone-platform=x11 --ignore-gpu-blocklist --enable-gpu-rasterization --password-store=gnome %U

For workspace autoswitch, save autoswitch.sh script in ~/.config/hypr/scripts directory and make it executable with below command, then save hypr-autoswitch.service file in ~/.config/systemd/user directory and enable the service

      chmod +x ~/.config/hypr/scripts/autoswitch.sh

      systemctl --user daemon-reload

      systemctl --user enable hypr-autoswitch.service

Save Battery notification script in ~/.config/hypr/scripts and make it executable, the exec-once for the script is added in config

      chmod +x ~/.config/hypr/scripts/battery-notify.sh

To decrease boot order timeout prompt of systemd while rebooting, switch to root and change timeout to 2 (or 0 to disable completly) in /boot/loader/loader.conf
