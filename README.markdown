This Puppet module is extracted from [Chiselwrigt's puppet-postgresql repo](https://github.com/chiselwright/puppet-postgresql). That package does a lot of neat things, but I could never get it to work.

So I took the best concepts from it and pulled them into this minimalist package.

It has opinions.

It's meant specifically for Ubuntu Lucid/Precise/Trusty,  for example.

It's also small enough you can fix it when something goes wrong (unlike the puppet-postgresql package) - even if you don't really know Puppet.

Requires: 'apt' puppet package

Using It
=============================


    postgresql::user {"superman":
      ensure => present,
      superuser => true,
    }

    postgresql::database {"fortress":
      ensure => present,
      owner => "vagrant",
      require => Postgresql::User["superman"]
    }
