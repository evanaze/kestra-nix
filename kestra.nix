let
  module = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.kestra;

    settingsFormat = pkgs.formats.yaml {};

    effectivePluginPath =
      if cfg.pluginPath == null
      then "${cfg.stateDir}/plugins"
      else cfg.pluginPath;

    isSecretLeaf = value:
      builtins.isAttrs value
      && value ? "_secret"
      && builtins.isString (toString value._secret)
      && (lib.length (lib.attrNames (lib.removeAttrs value ["_secret"])) == 0);

    substituteSecrets = value: keyPath:
      if builtins.isAttrs value
      then
        if isSecretLeaf value
        then let
          token = "__KES_SECRET_${builtins.hashString "sha256" (builtins.toJSON keyPath)}__";
        in {
          value = token;
          secrets = [
            {
              token = token;
              path = toString value._secret;
            }
          ];
        }
        else let
          children =
            lib.mapAttrsToList (name: child: {
              name = name;
              data = substituteSecrets child (keyPath ++ [name]);
            })
            value;
        in {
          value = lib.listToAttrs (
            map (child: {
              name = child.name;
              value = child.data.value;
            })
            children
          );
          secrets = lib.concatMap (child: child.data.secrets) children;
        }
      else if builtins.isList value
      then let
        children =
          lib.imap1 (
            index: child:
              substituteSecrets child (
                keyPath
                ++ [
                  toString
                  index
                ]
              )
          )
          value;
      in {
        value = map (child: child.value) children;
        secrets = lib.concatMap (child: child.secrets) children;
      }
      else {
        value = value;
        secrets = [];
      };
  in {
    options.services.kestra = {
      enable = lib.mkEnableOption "Kestra workflow orchestration service";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/kestra {};
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/kestra {}";
        description = "Kestra package to use for the service.";
      };

      settings = lib.mkOption {
        type = settingsFormat.type;
        default = {};
        example = {
          micronaut.server.host = "127.0.0.1";
          datasources.postgres.url = "jdbc:postgresql://127.0.0.1:5432/kestra";
          datasources.postgres.username = "kestra";
          datasources.postgres.password._secret = "/run/secrets/kestra/db-password";
          kestra.encryption.secret-key._secret = "/run/secrets/kestra/encryption-secret-key";
          kestra.secret.jdbc.secret._secret = "/run/secrets/kestra/jdbc-secret-key";
        };
        description = ''
          Configuration passed to `kestra server standalone --config`.

          For secret values, use `{ _secret = "/run/secrets/..."; }` style leaves:
          `field._secret = "/path/to/secret"`. Secret values are substituted at
          service start time into a generated runtime config under
          `runtimeConfigFile`.
        '';
      };

      databaseName = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "PostgreSQL database name for Kestra.";
      };

      databaseUser = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "PostgreSQL user for Kestra.";
      };

      databaseHost = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host for Kestra connections.";
      };

      databasePort = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port for Kestra connections.";
      };

      databasePasswordSecret = lib.mkOption {
        type = lib.types.str;
        default = "kestra/db-password";
        description = "sops secret name/path for the Kestra PostgreSQL password.";
      };

      encryptionSecretKey = lib.mkOption {
        type = lib.types.str;
        default = "kestra/encryption-secret-key";
        description = "sops secret name/path for `kestra.encryption.secret-key`.";
      };

      jdbcSecretKey = lib.mkOption {
        type = lib.types.str;
        default = "kestra/jdbc-secret-key";
        description = "sops secret name/path for `kestra.secret.jdbc.secret`.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "System user for the Kestra service.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "System group for the Kestra service.";
      };

      stateDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/kestra";
        description = "Directory for Kestra runtime state and files.";
      };

      pluginPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Plugin directory passed to `--plugins` on startup.

          If unset (`null`), defaults to `stateDir`/`plugins`.
        '';
      };

      runtimeConfigFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/kestra/application.yaml";
        description = "Runtime destination for the generated Kestra YAML configuration.";
      };
    };

    config = lib.mkIf cfg.enable (
      let
        dbPasswordSecretPath = config.sops.secrets."${cfg.databasePasswordSecret}".path;
        encryptionSecretPath = config.sops.secrets."${cfg.encryptionSecretKey}".path;
        jdbcSecretPath = config.sops.secrets."${cfg.jdbcSecretKey}".path;

        defaultSettings = {
          micronaut.server.host = "127.0.0.1";

          datasources.postgres = {
            url =
              "jdbc:postgresql://" + cfg.databaseHost + ":" + toString cfg.databasePort + "/" + cfg.databaseName;
            "driver-class-name" = "org.postgresql.Driver";
            username = cfg.databaseUser;
            password._secret = dbPasswordSecretPath;
          };

          kestra.repository.type = "postgres";
          kestra.queue.type = "postgres";
          kestra.storage.type = "local";
          kestra.storage.local.base-path = "${cfg.stateDir}/storage";
          kestra.encryption.secret-key._secret = encryptionSecretPath;
          kestra.secret.type = "jdbc";
          kestra.secret.jdbc.secret._secret = jdbcSecretPath;
        };
        effectiveSettings = lib.recursiveUpdate defaultSettings cfg.settings;
        normalizedSettings = substituteSecrets effectiveSettings [];
        settingsTemplate = settingsFormat.generate "kestra-application-template.yaml" normalizedSettings.value;
      in {
        users.groups.${cfg.group} = {};
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.stateDir;
        };

        sops.secrets = {
          "${cfg.databasePasswordSecret}" = {
            owner = cfg.user;
            group = "postgres";
            mode = "0640";
          };
          "${cfg.encryptionSecretKey}" = {
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
          "${cfg.jdbcSecretKey}" = {
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        };

        services.postgresql = {
          ensureDatabases = [cfg.databaseName];
          ensureUsers = [
            {
              name = cfg.databaseUser;
              ensureDBOwnership = true;
              ensureClauses = {
                login = true;
              };
            }
          ];
          authentication = lib.mkOverride 10 (
            lib.mkAfter ''
              # Kestra authentication rule (TCP, localhost only)
              host ${cfg.databaseName} ${cfg.databaseUser} 127.0.0.1/32 scram-sha-256
              host ${cfg.databaseName} ${cfg.databaseUser} ::1/128 scram-sha-256
            ''
          );
        };

        systemd.services.kestra-db-init = {
          after = [
            "postgresql.service"
            "sops-secrets.target"
          ];
          requires = [
            "postgresql.service"
            "sops-secrets.target"
          ];
          description = "Set Kestra PostgreSQL role password";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Group = "postgres";
          };
          script = ''
            set -euo pipefail

            PSQL="${lib.getExe' config.services.postgresql.package "psql"}"
            DB_PASSWORD_PATH='${dbPasswordSecretPath}'

            DB_PASSWORD="$(tr -d '\n' < "$DB_PASSWORD_PATH")"

            "$PSQL" --set=ON_ERROR_STOP=1 \
              -v "kestra_db_name=${cfg.databaseName}" \
              -v "kestra_db_user=${cfg.databaseUser}" \
              -v "kestra_db_password=$DB_PASSWORD" \
              --dbname=postgres <<'SQL'
              SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'kestra_db_user', :'kestra_db_password') \gexec;
              SELECT format('ALTER DATABASE %I OWNER TO %I', :'kestra_db_name', :'kestra_db_user') \gexec;
            SQL
          '';
        };

        systemd.services.kestra = {
          description = "Kestra workflow orchestrator";
          after = [
            "network.target"
            "postgresql.service"
            "sops-secrets.target"
            "kestra-db-init.service"
          ];
          wants = [
            "postgresql.service"
            "sops-secrets.target"
            "kestra-db-init.service"
          ];
          requires = [
            "postgresql.service"
            "sops-secrets.target"
            "kestra-db-init.service"
          ];
          wantedBy = ["multi-user.target"];

          preStart = ''
                      mkdir -p '${dirOf cfg.runtimeConfigFile}'
                      chmod 0700 '${dirOf cfg.runtimeConfigFile}'

                      mkdir -p '${cfg.stateDir}'
                      chmod 0750 '${cfg.stateDir}'

                      mkdir -p '${effectivePluginPath}'
                      chmod 0750 '${effectivePluginPath}'

                      ${lib.getExe pkgs.python3} - '${settingsTemplate}' '${cfg.runtimeConfigFile}' '${builtins.toJSON normalizedSettings.secrets}' <<'PY'
            from pathlib import Path
            import json
            import sys


            template_path = Path(sys.argv[1])
            runtime_path = Path(sys.argv[2])
            replacements = json.loads(sys.argv[3])

            config = template_path.read_text()
            for replacement in replacements:
              token = replacement["token"]
              secret_path = replacement["path"]
              value = Path(secret_path).read_text().rstrip("\n")
              config = config.replace(token, value)

            runtime_path.write_text(config)
            PY

                      chmod 0600 '${cfg.runtimeConfigFile}'
                      chown ${cfg.user}:${cfg.group} '${cfg.runtimeConfigFile}'
          '';

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.stateDir;
            Environment = {
              HOME = cfg.stateDir;
              KESTRA_PLUGINS_PATH = effectivePluginPath;
            };
            ExecStart = "${lib.getExe cfg.package} server standalone --config ${cfg.runtimeConfigFile} --plugins ${effectivePluginPath}";
            Restart = "always";
            RestartSec = 5;
            KillMode = "mixed";
            TimeoutStopSec = 150;
            SuccessExitStatus = "143";
            StateDirectory = "kestra";
            StateDirectoryMode = "0750";
            ReadWritePaths = [
              cfg.stateDir
              effectivePluginPath
            ];
          };
        };
      }
    );
  };
in {
  flake.modules.nixos = {
    servicesKestra = module;
  };
}
