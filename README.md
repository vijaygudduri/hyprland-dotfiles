1.  **Install sddm and enable it, and install kitty**

      ```bash
      sudo pacman -S sddm kitty
      ```

      ```bash   
      sudo systemctl enable sddm
      ```

2.  **Install nwg-drawer and nwg-look, the keybind SUPER+D is added in config for nwg-drawer**

      ```bash      
      sudo pacman -S nwg-drawer nwg-look
      ```

3.  **Install hyprpanel and paste the config file content in ~/.config/hyprpanel/config.jsonc, exec-once for hyprpanel is added in config. For custom netspeed, the script is added, make it executable**

      ```bash
      paru -S ags-hyprpanel-git
      ```

      ```bash 
      paru -S --needed aylurs-gtk-shell-git wireplumber libgtop bluez bluez-utils btop networkmanager dart-sass wl-clipboard brightnessctl swww python upower pacman-contrib power-profiles-daemon gvfs gtksourceview3 libsoup3 grimblast-git wf-recorder-git hyprpicker matugen-bin python-gpustat hyprsunset-git
      ```

4.  **Install gnome polkit (authentication agent) and gnome keyring (password store), the exec-once for polkit and keyring are added in config**

      ```bash
      sudo pacman -S polkit-gnome gnome-keyring
      ```

5.  **Install xdg-desktop-portal-hyprland, the env's are added in config**

      ```bash
      sudo pacman -S xdg-desktop-portal-hyprland
      ```

6.  **Install hypridle, hyprlock, hyprpaper, the config files and exec-once are added**

      ```bash 
      sudo pacman -S hypridle hyprlock hyprpaper 
      ```

7.  **Install cliphist for clipboard manager, the exec-once are added in config**

      ```bash
      sudo pacman -S cliphist
      ```

8.  **Install sugar-candy theme for sddm and catppuccin, tokyo night gtk themes and tela dracula icon theme and bibata cursor theme (apply these gtk, icon and cursor themes using nwg-look)**

      ```bash
      paru -S sddm-sugar-candy-git tokyonight-gtk-theme-git catppuccin-gtk-theme-mocha tela-circle-icon-theme-dracula bibata-cursor-theme
      ```

9.  **To apply sugar-candy theme on sddm, add below in /etc/sddm.conf.d/sddm.conf file, if the file doesn't exist by default then create one**

      ```bash      
      [General]
      Numlock=on

      [Theme]
      Current=sugar-candy
      CursorTheme=Bibata-Modern-Ice
      CursorSize=24
      ```

10.  **Copy brave-browser.desktop file from /usr/share/applications to ~/.local/share/applications and add the below flags in exec line**

      ```bash
      Exec=brave --enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,UseOzonePlatform --ozone-platform=x11 --ignore-gpu-blocklist --enable-gpu-rasterization --password-store=gnome %U
      ```

11.  **For workspace autoswitch, save autoswitch.sh script in ~/.config/hypr/scripts directory and make it executable with below command, then save hypr-autoswitch.service file in ~/.config/systemd/user directory and enable the service**

      ```bash
      sudo pacman -S socat; chmod +x ~/.config/hypr/scripts/autoswitch.sh
      ```

      ```bash
      systemctl --user daemon-reload
      systemctl --user enable hypr-autoswitch.service
      ```

12.  **Save Battery notification and Bluetooth auto-connect scripts in ~/.config/hypr/scripts and make those executable, the exec-once for the scripts are added in config. Also make other scripts executable**

      ```bash
      chmod +x ~/.config/hypr/scripts/battery-notify.sh ~/.config/hypr/scripts/bluetooth-autoconnect.sh ~/.config/hypr/scripts/hyprpanel-custom-netspeed.sh ~/.config/fastfetch/fastfetch.sh
      ```

13.  **To decrease boot order timeout prompt of systemd while rebooting, switch to root and change timeout to 2 (or 0 to disable completly) in /boot/loader/loader.conf**

14.  **Currently installed apps**

      ```bash
      sudo pacman -S brave-bin network-manager-applet gnome-calculator gnome-text-editor gnome-clocks blueman nautilus libreoffice-fresh telegram-desktop transmission-gtk smplayer swappy evince
      ```

      ```bash
      paru -S visual-studio-code-bin zoom
      ``` 

15.  **Change to google dns**

      ```bash
      nmcli con mod 'Android' ipv4.dns '8.8.8.8 8.8.4.4'
      nmcli con mod 'Android' ipv6.dns '2001:4860:4860::8888 2001:4860:4860::8844'
      nmcli con up 'Android'
      ```
