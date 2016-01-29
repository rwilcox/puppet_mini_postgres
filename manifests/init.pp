include 'apt'


class mini_postgres {

  user { "postgres":
    ensure => present,
/*    require => Package["postgresql"], */
  }


  $data_dir = $postgresql_data_dir ? {
    "" => "/var/lib/postgresql",
    default => $postgresql_data_dir,
  }

  case $lsbdistcodename {
    "lucid", "precise" : {

      # for apt add-apt-repository
      package{"add-apt":
        name => "python-software-properties",
        ensure => present
      }

      # Use official PostgresQL PPA to pull in new Postgres in Lucid
      apt::ppa { 'ppa:pitti/postgresql':
        options => "",
        require => Package["add-apt"],
        notify => Exec["apt-get update"]
      }

      exec {"apt-get update":
        command => "/usr/bin/apt-get update",
        user => "root",
        logoutput => on_failure
      }

      package {[
        "libpq-dev",
        "libpq5",
        "postgresql-client-9.2",
        "postgresql-common",
        "postgresql-client-common",
        "postgresql-contrib-9.2"
        ]:
        ensure  => present,
        require => [ Apt::Ppa["ppa:pitti/postgresql"], Exec["apt-get update"] ]
      }

      package{"postgresql":
        ensure => present,
        name => "postgresql-9.2",
        notify => Exec["pg_createcluster in utf8"],
        require => Apt::Ppa["ppa:pitti/postgresql"]
      }

      # re-create the cluster in UTF8
      exec {"pg_createcluster in utf8" :
        command => "pg_dropcluster --stop 9.2 main && pg_createcluster -e UTF8 --locale=en_US.utf8 -d ${data_dir}/9.2/main --start 9.2 main",
        onlyif => "test \$(su -c \"psql -tA -c 'SELECT count(*)=3 AND min(encoding)=0 AND max(encoding)=0 FROM pg_catalog.pg_database;'\" postgres) = t",
        user => root,
        timeout => 60,
      }


    }

    default: {
      fail "postgresql 9.2 not available for ${operatingsystem}/${lsbdistcodename}"
    }
  }


}


/*

==Definition: postgresql::database

Create a new PostgreSQL database

*/
define postgresql::database(
  $ensure=present,
  $owner=false,
  $encoding=false,
  $template="template1",
  $source=false,
  $overwrite=false) {

  $ownerstring = $owner ? {
    false => "",
    default => "-O $owner"
  }

  $encodingstring = $encoding ? {
    false => "",
    default => "-E $encoding",
  }

  case $ensure {
    present: {
      exec { "Create $name postgres db":
        command => "/usr/bin/createdb $ownerstring $encodingstring $name -T $template",
        user    => "postgres",
        unless  => "test \$(psql -tA -c \"SELECT count(*)=1 FROM pg_catalog.pg_database where datname='${name}';\") = t",
        require => Package["postgresql"],
      }
    }
    absent:  {
      exec { "Remove $name postgres db":
        command => "/usr/bin/dropdb $name",
        user    => "postgres",
        onlyif  => "test \$(psql -tA -c \"SELECT count(*)=1 FROM pg_catalog.pg_database where datname='${name}';\") = t",
        require => Package["postgresql"],
      }
    }
    default: {
      fail "Invalid 'ensure' value '$ensure' for postgres::database"
    }
  }

  # Drop database before import
  if $overwrite {
    exec { "Drop database $name before import":
      command => "dropdb ${name}",
      onlyif  => "/usr/bin/psql -l | grep '$name  *|'",
      user    => "postgres",
      before  => Exec["Create $name postgres db"],
      require => Package["postgresql"],
    }
  }

  # Import initial dump
  if $source {
    # TODO: handle non-gziped files
    exec { "Import dump into $name postgres db":
      command => "zcat ${source} | psql ${name}",
      user => "postgres",
      onlyif => "test $(psql ${name} -c '\\dt' | wc -l) -eq 1",
      require => Exec["Create $name postgres db"],
    }
  }
}


/*

==Definition: postgresql::user

Create a new PostgreSQL user

*/
define postgresql::user(
  $ensure=present,
  $password=false,
  $superuser=false,
  $createdb=false,
  $createrole=false,
  $hostname='/var/run/postgresql',
  $port='5432',
  $user='postgres') {

  $pgpass = $password ? {
    false   => "",
    default => "$password",
  }

  $superusertext = $superuser ? {
    false   => "NOSUPERUSER",
    default => "SUPERUSER",
  }

  $createdbtext = $createdb ? {
    false   => "NOCREATEDB",
    default => "CREATEDB",
  }

  $createroletext = $createrole ? {
    false   => "NOCREATEROLE",
    default => "CREATEROLE",
  }

  # Connection string
  $connection = "-h ${hostname} -p ${port} -U ${user}"

  case $ensure {
    present: {

      # The createuser command always prompts for the password.
      # User with '-' like www-data must be inside double quotes
      exec { "Create postgres user $name":
        command => $password ? {
          false => "psql ${connection} -c \"CREATE USER \\\"$name\\\" \" ",
          default => "psql ${connection} -c \"CREATE USER \\\"$name\\\" PASSWORD '$password'\" ",
        },
        user    => "postgres",
        unless  => "psql ${connection} -c '\\du' | egrep '^  *$name '",
        require => [User["postgres"], Package["postgresql"]],
      }

      exec { "Set SUPERUSER attribute for postgres user $name":
        command => "psql ${connection} -c 'ALTER USER \"$name\" $superusertext' ",
        user    => "postgres",
        unless  => "psql ${connection} -tc \"SELECT rolsuper FROM pg_roles WHERE rolname = '$name'\" |grep -q $(echo $superuser |cut -c 1)",
        require => [User["postgres"], Exec["Create postgres user $name"]],
      }

      # TODO: fix me???? This causes fun error, but shouldn't??? matter.
      # Ask Postgres expert (I'm not). WD-rpw 12-29-2013
      #exec { "Set CREATEDB attribute for postgres user $name":
      #  command => "psql ${connection} -c 'ALTER USER \"$name\" $createdbtext' ",
      #  user    => "postgres",
      #  unless  => "psql ${connection} -tc \"SELECT rolcreatedb FROM pg_roles WHERE rolname = '$name'\" |grep -q $(echo $createdb |cut -c 1)",
      #  require => [User["postgres"], Exec["Create postgres user $name"]],
      #}

      exec { "Set CREATEROLE attribute for postgres user $name":
        command => "psql ${connection} -c 'ALTER USER \"$name\" $createroletext' ",
        user    => "postgres",
        unless  => "psql ${connection} -tc \"SELECT rolcreaterole FROM pg_roles WHERE rolname = '$name'\" |grep -q $(echo $createrole |cut -c 1)",
        require => [User["postgres"], Exec["Create postgres user $name"]],
      }

      if $password {
        $host = $hostname ? {
          '/var/run/postgresql' => "localhost",
          default               => $hostname,
        }

        # change only if it's not the same password
        exec { "Change password for postgres user $name":
          command => "psql ${connection} -c \"ALTER USER \\\"$name\\\" PASSWORD '$password' \"",
          user    => "postgres",
          unless  => "test $(TMPFILE=$(mktemp /tmp/.pgpass.XXXXXX) && echo '${host}:${port}:template1:${name}:${pgpass}' > \$TMPFILE && PGPASSFILE=\$TMPFILE psql -h ${host} -p ${port} -U ${name} -c '\\q' template1 && rm -f \$TMPFILE)",
          require => [User["postgres"], Exec["Create postgres user $name"]],
        }
      }

    }

    absent:  {
      exec { "Remove postgres user $name":
        command => "psql ${connection} -c 'DROP USER \"$name\" ' ",
        user    => "postgres",
        onlyif  => "psql ${connection} -c '\\du' | grep '$name  *|'",
        require => Package["postgresql"],
      }
    }

    default: {
      fail "Invalid 'ensure' value '$ensure' for postgres::user"
    }
  }
}
