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

RUN mkdir -p /home/warashi/.cache/go-build /home/warashi/go/pkg/mod

RUN curl -fsSL https://gh.io/copilot-install | bash

RUN curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-channel-add
RUN mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
ENV PATH="/home/warashi/.local/bin:/home/warashi/.nix-profile/bin:${PATH}"

COPY --chown=warashi:warashi --chmod=0755 <<'EOF' /home/warashi/.local/bin/chelly-entrypoint
#!/bin/sh

if [ -f flake.nix ]; then
  exec nix develop --accept-flake-config --command "$@"
elif [ -f shell.nix ]; then
  exec nix-shell --run "$*"
else
  exec "$@"
fi
EOF

RUN mkdir -p /home/warashi/.config/git && touch /home/warashi/.config/git/config
RUN git config --global user.name 'Shinnosuke Sawada-Dazai'
RUN git config --global user.email '3600530+Warashi@users.noreply.github.com'

ENTRYPOINT ["/home/warashi/.local/bin/chelly-entrypoint"]
CMD ["/bin/bash", "--login"]
