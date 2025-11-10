1.  **Install hyprland, sddm, brave and kitty**

      ```bash
      sudo pacman -S hyprland sddm kitty brave-bin; sudo systemctl enable sddm
      ```

2.  **Login to github, add new ssh key and clone the repo**

      ```bash
      ssh-keygen -t ed25519 -C "vijayg0127@gmail.com" #copy public key and paste in github
      ```

      ```bash
      git clone git@github.com:vijaygudduri/hyprland-dotfiles.git
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

5.  **Make all the scripts executable**

      ```bash
      chmod +x ~/.config/hypr/scripts/*
      ```

6.  **Apply themes from nwg-look**

7.  **To apply sugar-candy theme on sddm, add below in /etc/sddm.conf.d/sddm.conf file, if the file doesn't exist by default then create one**

      ```bash      
      [General]
      Numlock=on

      [Theme]
      Current=sugar-candy
      CursorTheme=Bibata-Modern-Ice
      CursorSize=24
      ```

8.  **For workspace autoswitch functionality, enable the service**

      ```bash
      systemctl --user daemon-reload
      systemctl --user enable hypr-autoswitch.service
      ```

9.  **To decrease boot order timeout prompt of systemd while rebooting, switch to root and change timeout to 2 (or 0 to disable completly) in /boot/loader/loader.conf**

10.  **Change to google dns**

      ```bash
      nmcli con mod 'Android' ipv4.dns '8.8.8.8 8.8.4.4'
      nmcli con mod 'Android' ipv6.dns '2001:4860:4860::8888 2001:4860:4860::8844'
      nmcli con up 'Android'
      ```

11.  **Switch to sudo and add starship config in fish**

      ```bash
      echo 'starship init fish | source' >> /usr/share/cachyos-fish-config/cachyos-config.fish
      ```
