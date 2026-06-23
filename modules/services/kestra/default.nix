{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.kestra;
  defaultPackage =
    if pkgs ? kestra
    then pkgs.kestra
    else pkgs.callPackage ../../../kestra {};

  defaultStateDir = "/var/lib/kestra";

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
                toString index
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

  # Resolve JDBC URL: explicit jdbcUrl takes precedence.
  resolvedJdbcUrl =
    if cfg.database.jdbcUrl != null
    then cfg.database.jdbcUrl
    else
      "jdbc:postgresql://"
      + cfg.database.host
      + ":"
      + toString cfg.database.port
      + "/"
      + cfg.database.name;

  # Build default Kestra settings.
  defaultSettings = {
    micronaut.server.host = "127.0.0.1";

    datasources.postgres = {
      url = resolvedJdbcUrl;
      "driver-class-name" = "org.postgresql.Driver";
      username = cfg.database.user;
      password._secret = cfg.database.passwordFile;
    };

    kestra.repository.type = "postgres";
    kestra.queue.type = "postgres";
    kestra.storage.type = "local";
    kestra.storage.local.base-path = "${cfg.stateDir}/storage";
    kestra.encryption.secret-key._secret = cfg.encryptionSecretKeyFile;
    kestra.secret.type = "jdbc";
    kestra.secret.jdbc.secret._secret = cfg.jdbcSecretKeyFile;
  };
  effectiveSettings = lib.recursiveUpdate defaultSettings cfg.settings;
  normalizedSettings = substituteSecrets effectiveSettings [];
  # Map secret paths to credential locations for runtime resolution.
  resolvedSecrets =
    map (s: {
      token = s.token;
      path = s.path;
    })
    normalizedSettings.secrets;
  settingsTemplate = settingsFormat.generate "kestra-application-template.yaml" normalizedSettings.value;
in {
  options.services.kestra = {
    enable = lib.mkEnableOption "Kestra workflow orchestration service";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
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

        This option is merged after all generated Kestra defaults (including
        database settings from ``database.*``), so it can intentionally
        override any generated value.
      '';
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          When ``true``, the module enables and provisions a local PostgreSQL
          database for Kestra: it sets
          ``services.postgresql.enable``, creates the database and user via
          ``services.postgresql.ensureDatabases`` /
          ``ensureUsers``, adds authentication rules, and defines
          ``kestra-db-init.service``.

          When ``false`` (the default), the module assumes an external
          PostgreSQL instance and does not configure or depend on local
          PostgreSQL in any way.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host for Kestra connections.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port for Kestra connections.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "PostgreSQL database name for Kestra.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "kestra";
        description = "PostgreSQL user for Kestra.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.externalPath;
        default = "/run/secrets/kestra/db-password";
        description = ''
          File containing the PostgreSQL password for the Kestra database user.

          The module provides this file to both ``kestra-db-init.service``
          (as ``postgres``) via systemd ``LoadCredential`` and to
          ``kestra.service`` by reading the configured path directly during
          ``preStart``.  The file therefore must be readable by the Kestra
          service user (``${cfg.user}``) as well as by whatever user manages
          database initialization.
        '';
      };

      jdbcUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Full JDBC URL override for the Kestra PostgreSQL datasource.

          When set, this replaces the URL auto-generated from
          ``database.host``, ``database.port``, and ``database.name``.
        '';
      };
    };

    encryptionSecretKeyFile = lib.mkOption {
      type = lib.types.externalPath;
      default = "/run/secrets/kestra/encryption-secret-key";
      description = ''
        File containing the value for ``kestra.encryption.secret-key``.

        This file must be readable by the Kestra service user.
      '';
    };

    jdbcSecretKeyFile = lib.mkOption {
      type = lib.types.externalPath;
      default = "/run/secrets/kestra/jdbc-secret-key";
      description = ''
        File containing the value for ``kestra.secret.jdbc.secret``.

        This file must be readable by the Kestra service user.
      '';
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
      default = defaultStateDir;
      description = ''
        Directory for Kestra runtime state and files.

        The default path is managed by systemd ``StateDirectory``. Custom paths
        are created and owned for the Kestra service user with tmpfiles rules.
      '';
    };

    pluginPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Plugin directory passed to ``--plugins`` on startup.

        If unset (``null``), defaults to ``stateDir``/``plugins``. Custom paths
        must be writable by the Kestra service user at startup.
      '';
    };

    runtimeConfigFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/kestra/application.yaml";
      description = "Runtime destination for the generated Kestra YAML configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = {};
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${effectivePluginPath} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    # Local PostgreSQL provisioning (gated by createLocally).
    services.postgresql = lib.mkIf cfg.database.createLocally (
      let
        pgUser = cfg.database.user;
        pgDb = cfg.database.name;
      in {
        enable = true;
        ensureDatabases = [pgDb];
        ensureUsers = [
          {
            name = pgUser;
            ensureDBOwnership = true;
            ensureClauses = {
              login = true;
            };
          }
        ];

        authentication = lib.mkAfter ''
          # Kestra authentication rule (TCP, localhost only)
          host ${pgDb} ${pgUser} 127.0.0.1/32 scram-sha-256
          host ${pgDb} ${pgUser} ::1/128 scram-sha-256
        '';
      }
    );

    # kestra-db-init.service (only in local mode).
    systemd.services.kestra-db-init = lib.mkIf cfg.database.createLocally (
      let
        pgUser = cfg.database.user;
        pgDb = cfg.database.name;
        pgPasswordFile = cfg.database.passwordFile;
      in {
        description = "Set Kestra PostgreSQL role password and database owner";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
          LoadCredential = ["db-password=${pgPasswordFile}"];
          StateDirectory = "kestra-db-init";
        };
        script = ''
          set -euo pipefail

          PSQL="${lib.getExe' config.services.postgresql.package "psql"}"
          DB_PASSWORD_PATH="${"\$CREDENTIALS_DIRECTORY"}/db-password"

          DB_PASSWORD="$(tr -d '\n' < "$DB_PASSWORD_PATH")"

          "$PSQL" --set=ON_ERROR_STOP=1 \
            -v "kestra_db_name=${pgDb}" \
            -v "kestra_db_user=${pgUser}" \
            -v "kestra_db_password=$DB_PASSWORD" \
            --dbname=postgres <<'SQL'
            SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'kestra_db_user', :'kestra_db_password') \gexec;
            SELECT format('ALTER DATABASE %I OWNER TO %I', :'kestra_db_name', :'kestra_db_user') \gexec;
          SQL
        '';
      }
    );

    # kestra.service: depends on local DB in local mode, external in external mode.
    systemd.services.kestra = lib.mkMerge (
      lib.filter (x: x != null) [
        {
          description = "Kestra workflow orchestrator";
          after = ["network.target"];
          wants = ["network.target"];
          wantedBy = ["multi-user.target"];

          preStart = ''
            set -euo pipefail

            install -d -m 0700 '${dirOf cfg.runtimeConfigFile}'
            install -d -m 0750 '${effectivePluginPath}'

            ${lib.getExe pkgs.python3} - '${settingsTemplate}' '${cfg.runtimeConfigFile}' '${builtins.toJSON resolvedSecrets}' <<'PY'
            from pathlib import Path
            import json
            import os
            import sys
            import tempfile


            template_path = Path(sys.argv[1])
            runtime_path = Path(sys.argv[2])
            replacements = json.loads(sys.argv[3])

            config = template_path.read_text()
            for replacement in replacements:
                token = replacement["token"]
                secret_path = replacement["path"]
                value = Path(secret_path).read_text().rstrip("\n")
                config = config.replace(token, value)

            runtime_dir = runtime_path.parent
            fd, tmp_name = tempfile.mkstemp(
                prefix=f".{runtime_path.name}.",
                suffix=".tmp",
                dir=runtime_dir,
                text=True,
            )
            tmp_path = Path(tmp_name)
            try:
                with os.fdopen(fd, "w") as tmp_file:
                    os.fchmod(tmp_file.fileno(), 0o600)
                    tmp_file.write(config)
                    tmp_file.flush()
                    os.fsync(tmp_file.fileno())
                tmp_path.replace(runtime_path)
                os.chmod(runtime_path, 0o600)
            except Exception:
                try:
                    tmp_path.unlink()
                except FileNotFoundError:
                    pass
                raise
            PY
          '';

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.stateDir;
            Environment = [
              "HOME=${cfg.stateDir}"
              "KESTRA_PLUGINS_PATH=${effectivePluginPath}"
            ];
            ExecStart = "${lib.getExe cfg.package} server standalone --config ${cfg.runtimeConfigFile} --plugins ${effectivePluginPath}";
            Restart = "always";
            RestartSec = 5;
            KillMode = "mixed";
            TimeoutStopSec = 150;
            SuccessExitStatus = "143";
            RuntimeDirectory = "kestra";
            RuntimeDirectoryMode = "0700";
            StateDirectory = lib.mkIf (cfg.stateDir == defaultStateDir) "kestra";
            StateDirectoryMode = lib.mkIf (cfg.stateDir == defaultStateDir) "0750";
            ReadWritePaths = [
              cfg.stateDir
              effectivePluginPath
            ];
          };
        }
        (lib.mkIf cfg.database.createLocally {
          after = [
            "network.target"
            "postgresql.service"
            "kestra-db-init.service"
          ];
          wants = [
            "network.target"
            "postgresql.service"
            "kestra-db-init.service"
          ];
          requires = [
            "postgresql.service"
            "kestra-db-init.service"
          ];
        })
      ]
    );
  };
}
