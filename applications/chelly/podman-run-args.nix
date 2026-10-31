[
  # keep-sorted start
  "--cap-add=SYS_ADMIN,SETUID,SETGID"
  "--cpus=4"
  "--detach-keys=ctrl-^,ctrl-^"
  "--device=/dev/fuse"
  "--device=/dev/net/tun"
  # 未指定だと swap を含めて 2 倍まで使え、zram swap がホストの RAM を食う。
  "--memory-swap=8G"
  "--memory=8G"
  "--security-opt=label=disable"
  "--security-opt=seccomp=unconfined"
  "--security-opt=unmask=/proc/*"
  # keep-sorted end
]
