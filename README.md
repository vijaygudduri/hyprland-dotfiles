Install sddm and enable it (sudo pacman -S sddm, systemctl enable sddm), and install kitty (sudo pacman -S kitty)

Install nwg-drawer and nwg-look (sudo pacman -S nwg-drawer nwg-look), the keybind SUPER+D is added in config for nwg-drawer

Install hyprpanel and configure it, exec-once for hyprpanel is added in config

Install gnome polkit (authentication agent) and gnome keyring (password store) (sudo pacman -S polkit-gnome gnome-keyring), the exec-once for polkit is added in config, and the autostart for keyring is added in autostart.conf file

Install xdg-desktop-portal-hyprland (sudo pacman -S xdg-desktop-portal-hyprland), the env's are added in config

Install hypridle, hyprlock, hyprpaper (sudo pacman -S hypridle hyprlock hyprpaper), the config files and exec-once are added

Install cliphist for clipboard manager (sudo pacman -S cliphist), the exec-once are added in config

Install sugar-candy theme for sddm and catppuccin, tokyo night gtk themes and tela dracula icon theme (paru -S sddm-sugar-candy-git tokyonight-gtk-theme-git catppuccin-gtk-theme-mocha tela-circle-icon-theme-dracula)
Apply gtk theme and icon theme from nwg-look (GTK Settings) app
To apply sugar-candy theme on sddm, add below in /etc/sddm.conf.d/sddm.conf file, if the file doesn't exist by default then create one
        [General]
        Numlock=on
        
        [Theme]
        Current=sugar-candy
