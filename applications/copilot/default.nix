{
  pkgs,
  lib,
  config,
  ...
}:
let
  settings-overrides = (pkgs.formats.json { }).generate "copilot-settings-override.json" {
  };
in
{
  home = {
    activation = {
      warashi-copilot-settings-merger = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        merge() {
          local f files=()
          for f in "$@"; do [[ -f $f ]] && files+=("$f"); done

          ${lib.getExe pkgs.jq} -n '
              def deep_merge($a; $b):
                if ($a | type == "object") and ($b | type == "object") then
                  reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = deep_merge($a[$k]; $b[$k]))
                elif ($a | type == "array") and ($b | type == "array") then
                  ($a + $b) | unique
                else
                  $b
                end;
              reduce inputs as $item ({}; deep_merge(.; $item))
            ' "''${files[@]}"
        }

        run cp -a ${./copilot-instructions.md} ${config.home.homeDirectory}/.copilot/copilot-instructions.md
        if [ -f ${config.home.homeDirectory}/.copilot/settings.json ]; then
          run cp -a ${config.home.homeDirectory}/.copilot/settings.json ${config.home.homeDirectory}/.copilot/settings.json.backup
        fi
        run merge ${config.home.homeDirectory}/.copilot/settings.json ${settings-overrides} > ${config.home.homeDirectory}/.copilot/settings.json.tmp
        run mv ${config.home.homeDirectory}/.copilot/settings.json.tmp ${config.home.homeDirectory}/.copilot/settings.json
      '';
    };
  };
}
