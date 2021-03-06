#===============================================================================
#
#         FILE:  SIP.pm
#
#  DESCRIPTION:  PearlPBX SIP management API
#
#       AUTHOR:  Alex Radetsky (Rad), <rad@rad.kiev.ua>
#      COMPANY:  Net.Style
#      VERSION:  1.0
#      CREATED:  23.06.12
#      REVISION: 001 
#===============================================================================
=head1 NAME

PearlPBX::SIP

=head1 SYNOPSIS

	use PearlPBX::SIP;

=cut

package PearlPBX::SIP;

use 5.8.0;
use strict;
use warnings;

use DBI;
use Config::General; 
use JSON;
use NetSDS::Util::String; 

use version; our $VERSION = "1.00";
our @EXPORT_OK = qw();

#===============================================================================
#
=head1 CLASS METHODS

=over

=item B<new($configfilename)> - class constructor

    my $object = PearlPBX::Report->new(%options);

=cut

#-----------------------------------------------------------------------
sub new {

	my $class = shift; 
	
  my $conf = shift;

  my $this = {}; 

  unless ( defined ( $conf ) ) {
     $conf = '/etc/PearlPBX/asterisk-router.conf';
  }

  my $config = Config::General->new (
    -ConfigFile        => $conf,
    -AllowMultiOptions => 'yes',
    -UseApacheInclude  => 'yes',
    -InterPolateVars   => 'yes',
    -ConfigPath        => [ $ENV{PEARL_CONF_DIR}, '/etc/PearlPBX' ],
    -IncludeRelative   => 'yes',
    -IncludeGlob       => 'yes',
    -UTF8              => 'yes',
  );

  unless ( ref $config ) {
    return undef;
  }

  my %cf_hash = $config->getall or ();
  $this->{conf} = \%cf_hash;
  $this->{dbh} = undef;     # DB handler 
  $this->{error} = undef;   # Error description string    

	bless ( $this,$class ); 
	return $this;

};

#***********************************************************************
=head1 OBJECT METHODS

=over

=item B<db_connect(...)> - соединяется с базой данных. 
Возвращает undef в случае неуспеха или true если ОК.
DBH хранит в this->{dbh};  

=cut

#-----------------------------------------------------------------------

sub db_connect {
	my $this = shift; 
  
    unless ( defined( $this->{conf}->{'db'}->{'main'}->{'dsn'} ) ) {
        $this->{error} = "Can't find \"db main->dsn\" in configuration.";
        return undef;  
    }

    unless ( defined( $this->{conf}->{'db'}->{'main'}->{'login'} ) ) {
        $this->{error} = "Can't find \"db main->login\" in configuraion.";
        return undef;
    }

    unless ( defined( $this->{conf}->{'db'}->{'main'}->{'password'} ) ) {
        $this->{error} = "Can't find \"db main->password\" in configuraion.";
        return undef;
    }

    my $dsn    = $this->{conf}->{'db'}->{'main'}->{'dsn'};
    my $user   = $this->{conf}->{'db'}->{'main'}->{'login'};
    my $passwd = $this->{conf}->{'db'}->{'main'}->{'password'};

    # If DBMS isn' t accessible - try reconnect
    if ( !$this->{dbh} or !$this->{dbh}->ping ) {
        $this->{dbh} = 
            DBI->connect_cached( $dsn, $user, $passwd, { RaiseError => 1, AutoCommit => 0 } );
    }

    if ( !$this->{dbh} ) {
        $this->{error} = "Cant connect to DBMS!";
        return undef;
    }

    return 1;
};
=item B<list_internal> 

 возвращает HTML представление списка внутренних пользователей

=cut 
sub list_internal { 
	my $this = shift;
	my $sql = "select id,comment,name from public.sip_peers where name ~ E'2\\\\d\\\\d' order by name";

	return $this->_list($sql);
}

sub list_internalAsOption { 
  my $this = shift;
my $sql = "select id,comment,name from public.sip_peers where name ~ E'2\\\\d\\\\d' order by name";

  return $this->_listAsOption($sql);  
}
=item B<list_external> 

 возвращает HTML представление списка внешних транков 

=cut 
sub list_external { 
	my $this = shift; 
	my $sql = "select id,name,comment from public.sip_peers where name !~ E'2\\\\d\\\\d' order by name"; 

  return $this->_list($sql); 
}

sub _list { 
	my ($this, $sql) = @_; 

	my $sth = $this->{dbh}->prepare($sql); 
	eval { $sth->execute(); }; 
	if ( $@ ) {
	  print $this->{dbh}->errstr; 
		return undef; 
	}

	my $out = '<ul class="nav nav-tabs">';
  while ( my $row = $sth->fetchrow_hashref ) { 
		 unless ( defined ( $row->{'comment'} ) ) { 
		 	$row->{'comment'} = ''; 
		 } 
	   $out .= '<li><a href="#pearlpbx_sip_edit_user" data-toggle="modal" onClick="pearlpbx_sip_load_id('.$row->{'id'}.')">'.$row->{'comment'}.'&lt;'.$row->{'name'}.'&gt;'.'</a></li>';
	}		 
  $out .= "</ul>";
	return $out; 
}

sub _listAsOption { 
  my ($this, $sql) = @_; 

  my $sth = $this->{dbh}->prepare($sql); 
  eval { $sth->execute(); }; 
  if ( $@ ) {
    print $this->{dbh}->errstr; 
    return undef; 
  }

  my $out = '';
  while ( my $row = $sth->fetchrow_hashref ) { 
     unless ( defined ( $row->{'comment'} ) ) { 
      $row->{'comment'} = ''; 
     } 
     $out .= '<option value="'.$row->{'name'}.'">'.$row->{'comment'}.'&lt;'.$row->{'name'}.'&gt;</option>';
  }    
  return $out; 
}



=item B<list_internal_free> 

Возвращает список свободных внутренних номеров в виде списка option for select 

=cut 

sub list_internal_free { 
  my $this = shift; 

  my $sql = 'select freename from generate_series (200,299,1) as freename where freename::text not in ( select name from public.sip_peers);'; 
  my $sth = $this->{dbh}->prepare($sql); 
  eval { $sth->execute(); }; 
  if ( $@ ) {
    print $this->{dbh}->errstr; 
    return undef; 
  }
  my $out = '';
  while ( my $row = $sth->fetchrow_hashref ) {
    $out .= '<option value="'.$row->{'freename'}.'">'.$row->{'freename'}.'</option>';
  }
  return $out; 

}

=item B<newsecret>

 Генерирует новый пароль и возвращает его 

=cut 

sub newsecret { 
  my $this = shift; 

  return `pwgen -c 16`;

}

=item B<adduser>

 Добавляет нового пользователя в public.sip_peers. 
 Простой метод. Сложный будет доступен чуть позже, для advanced administrators и подозреваю, 
 что за деньги. Ибо для SMB-сектора текущего метода должно хватить.  

=cut 

sub adduser { 
  my ($this, $params) = @_;

  my $sql  = "insert into public.sip_peers (name, comment, secret, host, context ) values (?,?,?,?,?) returning id"; 
  my $sql2 = "insert into integration.workplaces (sip_id, teletype, autoprovision, mac_addr_tel ) 
    values (?,?,?,?)"; 

  unless ( defined ( $params->{'extension'} ) or 
         defined ( $params->{'comment'} ) or 
         defined ( $params->{'secret'} ) ) { 
    return "ERROR";
  }

  my $sth  = $this->{dbh}->prepare($sql);

  eval { 
    $sth->execute( 
      $params->{'extension'},
      $params->{'comment'},
      $params->{'secret'},
      'dynamic',
      'default',
    ); 
  };

  if ( $@ ) {
    return "ERROR:". $this->{dbh}->errstr;  
  }

  my $row = $sth->fetchrow_hashref; 
  my $sip_id = $row->{'id'};

  
  my $sth2 = $this->{dbh}->prepare($sql2);
  my $teletype = $params->{'terminal'};
  my $autoprovision = 'true';

  unless ( defined ( $params->{'terminal'})) { 
    $teletype = "softphone"; 
    $autoprovision = 'false';  
  } 

  eval { 
    $sth2->execute( 
      $sip_id, $teletype, $autoprovision, $params->{'macaddr'}
    ); 
  };

  if ( $@ ) {
    return "ERROR:". $this->{dbh}->errstr;  
  }

  eval { $this->{dbh}->commit;};
  if ( $@ ) {
    return "ERROR:". $this->{dbh}->errstr;  
  }
  return "OK";

}



sub getuser { 
  my ($this,$id) = @_; 

  my $sql = "select a.id, a.name as extension, a.comment, a.secret,
  b.teletype, b.mac_addr_tel from public.sip_peers a,
  integration.workplaces b where a.id=? and a.id=b.sip_id;";

  my $sth = $this->{dbh}->prepare($sql);
  eval { $sth->execute($id); }; 
  if ( $@ ) {
    return "ERROR:". $this->{dbh}->errstr;  
  }
  my $row = $sth->fetchrow_hashref; 
  $row->{'comment'} = str_encode($row->{'comment'}); 
  return encode_json($row);

}

sub setuser {

my ($this, $params) = @_;

  my $sql  = "update public.sip_peers set comment=?, secret=? where id=? "; 
  my $sql2 = "update integration.workplaces set teletype=?, autoprovision=?, mac_addr_tel=? where sip_id=?"; 

  my $autoprovision = 'true'; 

  if ( $params->{'terminal'} =~ /softphone/ ) { 
      $autoprovision = 'false';
  }

  unless ( defined ( $params->{'comment'} ) or defined ( $params->{'secret'} ) ) { 
    return "ERROR";
  }

  my $sth  = $this->{dbh}->prepare($sql);
  my $sth2 = $this->{dbh}->prepare($sql2);

  eval {$sth->execute($params->{'comment'}, $params->{'secret'}, $params->{'id'});};
  if ( $@ ) { return "ERROR:". $this->{dbh}->errstr; }

  eval { $sth2->execute($params->{'terminal'}, $autoprovision, $params->{'macaddr'}, $params->{'id'});}; 
  if ( $@ ) { return "ERROR:". $this->{dbh}->errstr; }

  $this->{dbh}->commit;
  return "OK";

}


1;

__END__

=back

=head1 EXAMPLES


=head1 BUGS

Unknown yet

=head1 SEE ALSO

None

=head1 TODO

None

=head1 AUTHOR

Alex Radetsky <rad@rad.kiev.ua>

=cut


