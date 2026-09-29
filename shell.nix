{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

let
  mysql = pkgs.mysql80;
  workbench = pkgs.mysql-workbench;

  # Pokreće samo MySQL server (inicijalizira bazu pri prvom pokretanju)
  mysql-up = pkgs.writeShellScriptBin "mysql-up" ''
    set -eu
    mkdir -p "$MYSQL_HOME"

    if [ ! -d "$MYSQL_DATADIR/mysql" ]; then
      echo ">> Inicijalizacija baze u $MYSQL_DATADIR (root bez lozinke)..."
      ${mysql}/bin/mysqld --no-defaults --initialize-insecure \
        --basedir=${mysql} \
        --datadir="$MYSQL_DATADIR" \
        --log-error="$MYSQL_HOME/init.log"
    fi

    if ${mysql}/bin/mysqladmin --no-defaults --socket="$MYSQL_SOCKET" -uroot ping >/dev/null 2>&1; then
      echo ">> MySQL server je već pokrenut."
      exit 0
    fi

    echo ">> Pokrećem MySQL server na 127.0.0.1:$MYSQL_TCP_PORT ..."
    nohup ${mysql}/bin/mysqld --no-defaults \
      --basedir=${mysql} \
      --datadir="$MYSQL_DATADIR" \
      --socket="$MYSQL_SOCKET" \
      --pid-file="$MYSQL_HOME/mysqld.pid" \
      --port="$MYSQL_TCP_PORT" \
      --bind-address=127.0.0.1 \
      --mysqlx=OFF \
      --log-error="$MYSQL_HOME/mysqld.log" \
      >/dev/null 2>&1 &

    for i in $(seq 1 60); do
      if ${mysql}/bin/mysqladmin --no-defaults --socket="$MYSQL_SOCKET" -uroot ping >/dev/null 2>&1; then
        echo ">> MySQL server je spreman."
        exit 0
      fi
      sleep 1
    done

    echo "!! Server se nije pokrenuo, pogledaj $MYSQL_HOME/mysqld.log" >&2
    exit 1
  '';

  # Zaustavlja MySQL server
  mysql-stop = pkgs.writeShellScriptBin "mysql-stop" ''
    ${mysql}/bin/mysqladmin --no-defaults --socket="$MYSQL_SOCKET" -uroot shutdown \
      && echo ">> MySQL server zaustavljen."
  '';

  # JEDNA KOMANDA: server + Workbench
  mysql-start = pkgs.writeShellScriptBin "mysql-start" ''
    set -eu
    ${mysql-up}/bin/mysql-up
    echo ">> Pokrećem MySQL Workbench..."
    echo ">> Konekcija: host 127.0.0.1, port $MYSQL_TCP_PORT, user root, bez lozinke"
    ${workbench}/bin/mysql-workbench "$@"
    echo ">> Workbench zatvoren. Server i dalje radi (zaustavi ga s: mysql-stop)"
  '';
in
pkgs.mkShell {
  name = "mysql-dev-shell";

  packages = [
    mysql
    workbench
    mysql-up
    mysql-stop
    mysql-start
  ];

  shellHook = ''
    export MYSQL_HOME="$PWD/.mysql"
    export MYSQL_DATADIR="$MYSQL_HOME/data"
    # Socket ide u /tmp jer unix socket putanja ima limit ~107 znakova
    export MYSQL_SOCKET="/tmp/mysql-nix-$USER.sock"
    export MYSQL_UNIX_PORT="$MYSQL_SOCKET"
    export MYSQL_TCP_PORT="''${MYSQL_TCP_PORT:-3306}"

    echo ""
    echo "MySQL nix shell spreman."
    echo "  mysql-start  -> pokreće server + Workbench"
    echo "  mysql-up     -> samo server"
    echo "  mysql-stop   -> zaustavlja server"
    echo "  mysql -uroot -> klijent u terminalu"
    echo ""
  '';
}
