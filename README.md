***Follow this after a fresh OS installation without any DE***

1.  **Install hyprland, sddm, brave and kitty**

      ```bash
      sudo pacman -S hyprland sddm kitty brave-bin; sudo systemctl enable sddm
      ```

2.  **Clone the repo**

      ```bash
      git clone https://github.com/vijaygudduri/hyprland-dotfiles.git
      ```

3.  **Install necessaries**

      ```bash      
      sudo pacman -S --needed nwg-drawer nwg-look waybar swaync polkit-gnome gnome-keyring xdg-desktop-portal-hyprland hypridle hyprlock hyprpaper cliphist socat jq starship network-manager-applet gnome-calculator gnome-text-editor gnome-clocks blueman nautilus libreoffice-fresh telegram-desktop transmission-gtk smplayer swappy evince brightnessctl hyprpicker hyprsunset cachyos-kernel-manager grimblast
      ```

      ```bash
      paru -S --needed sddm-sugar-candy-git catppuccin-gtk-theme-mocha tela-circle-icon-theme-dracula bibata-cursor-theme visual-studio-code-bin zoom
      ```

4.  **Copy the configs from cloned repo to ~/.config**

      ```bash
      cd ~/hyprland-dotfiles #cd to cloned repo
      ```

      ```bash
      cp -r hypr kitty fastfetch swaync systemd waybar brave-flags.conf ~/.config/
      ```
      
      ```bash
      cp -r wallpapers ~
      ```

5.  **Make all the scripts executable**

      ```bash
      chmod +x ~/.config/hypr/scripts/*
      ```

6.  **Apply themes from nwg-look**

7.  **To apply sugar-candy theme on sddm, run below commands**

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

9.  **For workspace autoswitch functionality, enable the service**

      ```bash
      systemctl --user daemon-reload
      systemctl --user enable hypr-autoswitch.service
      ```

10.  **To decrease boot order timeout prompt of systemd while rebooting, switch to root and change timeout to 2 (or 0 to disable completly) in /boot/loader/loader.conf**

11.  **Change to google dns, replace 'Android' with your connection name**

      ```bash
      nmcli con mod 'Android' ipv4.dns '8.8.8.8 8.8.4.4'
      nmcli con mod 'Android' ipv6.dns '2001:4860:4860::8888 2001:4860:4860::8844'
      nmcli con up 'Android'
      ```

12.  **Switch to sudo and add starship config in fish**

      ```bash
      echo 'starship init fish | source' >> /usr/share/cachyos-fish-config/cachyos-config.fish
      ```
