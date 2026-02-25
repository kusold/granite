# Hapi home-manager configuration
# Exports: flake.modules.homeManager.hapi
{ ... }:
{
  flake.modules.homeManager.hapi = { pkgs, ... }: {
    home.packages = [ pkgs.hapi ];

    systemd.user.services.hapi-hub = {
      Unit = {
        Description = "HAPI Hub";
        After = [ "network.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.hapi}/bin/hapi hub";
        Environment = "HAPI_LISTEN_HOST=0.0.0.0";
        Restart = "always";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    systemd.user.services.hapi-runner = {
      Unit = {
        Description = "HAPI Runner";
        After = [ "network.target" "hapi-hub.service" ];
        Requires = [ "hapi-hub.service" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.hapi}/bin/hapi runner start --foreground";
        Restart = "always";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
