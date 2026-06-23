FROM debian:stable

RUN apt-get update
RUN apt-get install -y sudo curl git bash xz-utils locales

ENV LANG=C.UTF-8

RUN groupadd -g 1000 warashi
RUN useradd -m -u 1000 -g warashi -G sudo -s /bin/bash warashi
RUN echo 'warashi ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER warashi
ENV USER=warashi
WORKDIR /home/warashi

RUN curl -fsSL https://gh.io/copilot-install | bash

RUN mkdir -p /home/warashi/.config/git && touch /home/warashi/.config/git/config
RUN git config --global user.name 'Shinnosuke Sawada-Dazai'
RUN git config --global user.email '3600530+Warashi@users.noreply.github.com'

RUN curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-channel-add
RUN mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
ENV PATH="/home/warashi/.nix-profile/bin:${PATH}"

CMD ["/bin/bash", "--login"]
