FROM archlinux:base
RUN pacman -Syu --noconfirm gtk4 libadwaita python-gobject xorg-server-xvfb xorg-xauth dbus ttf-dejavu noto-fonts adwaita-fonts adwaita-icon-theme python && pacman -Scc --noconfirm
RUN pacman -Sy --noconfirm orca python-atspi at-spi2-core speech-dispatcher espeak-ng && pacman -Scc --noconfirm
