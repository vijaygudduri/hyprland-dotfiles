***Follow this after a fresh OS installation without any DE (This is tested only on CachyOS)***

1.  **Install hyprland, sddm, chrome and kitty**

      ```bash
      sudo pacman -S hyprland sddm kitty ; sudo systemctl enable sddm
      ```

      ```bash
      paru -S google-chrome
      ```

2.  **Install necessaries**

      ```bash      
      sudo pacman -S --needed nwg-drawer nwg-look waybar swaync polkit-gnome gnome-keyring xdg-desktop-portal-hyprland hypridle hyprlock hyprpaper wl-clipboard socat jq starship network-manager-applet gnome-calculator gnome-text-editor gnome-clocks blueman nautilus onlyoffice-bin telegram-desktop transmission-gtk smplayer swappy evince brightnessctl hyprpicker hyprsunset cachyos-kernel-manager grimblast python-pydbus python-gobject python-dbus-next
      ```

      ```bash
      paru -S --needed sddm-sugar-candy-git catppuccin-gtk-theme-mocha bibata-cursor-theme visual-studio-code-bin zoom clipvault-bin
      ```

3.  **Compile and install syshud for osd**
      (this is available with aur, but its using audio engine wireplumber by default, so we are compiling it with pulseaudio as wireplumber giving some issues)

      ```bash
      git clone https://github.com/System64fumo/syshud.git
      cd syshud
      
      # replace WIREPLUMBER with PULSEAUDIO in src/config.hpp
      sed -i 's/WIREPLUMBER/PULSEAUDIO/g' src/config.hpp
      ```
      
      ```bash
      # compile and install
      make
      sudo make install
      
      # As manually compiled apps will be at /usr/local/lib, adding it to the system's library search paths
      echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/local.conf
      
      # Refresh the system's library cache to recognize the new files
      sudo ldconfig
      ```

4.  **Clone the dotfiles repo**

      ```bash
      git clone --depth=1 https://github.com/vijaygudduri/hyprland-dotfiles.git
      ```

5.  **Copy the configs from cloned repo to ~/.config**

      ```bash
      cd ~/hyprland-dotfiles #cd to cloned repo
      ```
      
      ```bash
      cp -ri wallpapers ~/ && cp -ri .config/. ~/.config/
      ```   

6.  **Make all the scripts executable**

      ```bash
      chmod +x ~/.config/scripts/*.sh ~/.config/scripts/*.py
      ```

7.  **Apply themes from nwg-look (theme is 'catppuccin mocha' and cursor theme is 'bibata modern ice')**

8.  **To apply sugar-candy theme on sddm, run below commands**

      ```bash
      sudo mkdir -p /etc/sddm.conf.d ; sudo touch /etc/sddm.conf.d/sddm.conf
      ```
      
      ```bash
      bash -c "sudo tee /etc/sddm.conf.d/sddm.conf > /dev/null <<'EOF'
      [General]
      Numlock=on
      
      [Theme]
      Current=sugar-candy
      CursorTheme=Bibata-Modern-Ice
      CursorSize=24
      EOF"
      ```

9.  **For workspace autoswitch functionality, enable the service (ignore this, as we are using python script with exec-once)**

      ```bash
      systemctl --user daemon-reload
      systemctl --user enable workspace-autoswitch.service
      ```

10.  **To decrease boot order timeout prompt of systemd while rebooting, switch to root and change timeout to 2 (or 0 to disable completly) in /boot/loader/loader.conf**

11.  **Change to google dns, replace 'Android' with your connection name**

      ```bash
      nmcli con mod 'Android' ipv4.dns '8.8.8.8 8.8.4.4'
      nmcli con mod 'Android' ipv6.dns '2001:4860:4860::8888 2001:4860:4860::8844'
      nmcli con up 'Android'
      ```

12.  **Add starship config and modify ls alias in fish**

      ```bash
      echo -e "\n\nalias ls='eza --color=always --group-directories-first --icons'\n\nstarship init fish | source" >> ~/.config/fish/config.fish
      ```


***Reboot after all the process is done***
