package Dancer::Plugin::Interchange5::SessionCrossover;

use warnings;
use strict;
use Dancer::Plugin;
use Dancer qw/:syntax/;
use Storable qw/thaw freeze/;

# this plugin nesting is not going to work with D2, until further notice :-\
use Dancer::Plugin::Database;

our $VERSION = '0.0001';

sub _get_session_id {
    my $name = plugin_setting->{cookie_name} || 'MV_SESSION_ID';
    my $code = cookie $name;
}

sub _read_key {
    my ($name, @keys) = @_;
    debug("$name, @keys");
    die "Name is mandatory to read a key!" unless (defined($name) && @keys);
    my $ref = _read_session($name);
    debug to_dumper($ref);
    return unless $ref;
    my @out;
    foreach my $k (@keys) {
        push @out, $ref->{$k};
    }
    wantarray ? return @out : return $out[0];
}


sub _write_key {
    my ($name, @args) = @_;
    die "Missing name" unless $name;

    # if no args is passed, just return without barfing
    return unless @args;
    # locking here
    die "Wrong usage! You have to pass pairs of keys/values to write in $name"
      if (@args % 2);

    my %data = @args;

    # get a fresh copy of the session
    my $freshdata = _read_session($name);

    # unlock and return
    # no session available
    return unless $freshdata;
    debug to_dumper($freshdata);

    foreach my $k (keys %data) {
        $freshdata->{$k} = $data{$k};
    }
    debug "Writing $name with above data";
    # replace
    my $exit = _write_session($name, $freshdata);
    
    # unlock

    return $exit;
}


sub _read_session {
    my ($self, @args) = plugin_args(@_);

    # 1. check for the cookie, if it's not there, we can't do anything
    my $code = _get_session_id;
    return unless $code;

    # 2. get the conf
    my $dbconf = _get_db_conf();

    # 3. read the session
    my $data = $dbconf->{dbh}->quick_select($dbconf->{table},
                                            { $dbconf->{code_column},  $code });

    # no data, return, but it's fishy
    return unless $data;

    # 4. deserialize
    my $session = thaw($data->{$dbconf->{session_column}});

    # 5. return the key if asked so, or the whole thing
    if (@args) {
        return $session->{$args[0]};
    }
    else {
        return $session;
    }
}

sub _write_session {
    my ($self, @args) = plugin_args(@_);
    my $code = _get_session_id;
    return unless $code;

    die ("Wrong usage, write_ic5_session wants two arguments, key and value")
      unless @args == 2;

    # Locking is missing right now
    my ($key, $val) = @args;
    
    # first, get a fresh copy of the session
    my $fresh_data = _read_session();

    # if we fail to get fresh data, the session is not available, so return
    return unless $fresh_data;
    
    # replace
    $fresh_data->{$key} = $val;

    # and store
    my $frozen = freeze($fresh_data);
    
    my $dbconf = _get_db_conf();
    $dbconf->{dbh}->quick_update($dbconf->{table},
                                 { $dbconf->{code_column}, $code },
                                 { $dbconf->{session_column}, $frozen });
    return $fresh_data;
}



sub _get_db_conf {
    # look up the configuration
    my $conf = plugin_setting || {};

    my %dbconf;

    # get the handler
    # no database key means use the default one for D::P::Database
    if ($conf->{database}) {
        $dbconf{dbh} = database($conf->{database});
    }
    else {
        $dbconf{dbh} = database;
    }

    die q{The table value } . __PACKAGE__ . " settings is mandatory"
      unless $conf->{table};
    # table name
    $dbconf{table} = $conf->{table};

    # hardcoded values
    $dbconf{code_column} = $conf->{code_column} || 'code';
    $dbconf{session_column} = $conf->{session_column} || 'session';
    return \%dbconf;
}


sub _get_conf {
    return plugin_setting() || {};
}


register read_ic5_session => sub {
    my ($self, @args) = plugin_args(@_);
    return _read_session(@args);
};

register write_ic5_session => sub {
    my ($self, @args) = plugin_args(@_);
    return _write_session(@args);
};

register read_ic5_scratch => sub {
    my ($self, @args) = plugin_args(@_);
    return _read_key(scratch => @args)
};

register write_ic5_scratch => sub {
    my ($self, @args) = plugin_args(@_);
    return _write_key(scratch => @args);
};

register read_ic5_value => sub {
    my ($self, @args) = plugin_args(@_);
    return _read_key(values => @args)
};

register write_ic5_value => sub {
    my ($self, @args) = plugin_args(@_);
    return _write_key(values => @args);
};

register ic5_values => sub {
    return _read_session('values');
};

register ic5_scratch => sub {
    return _read_session('scratch');
};


register_plugin;

1;
