use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack::AsyncClient;

=head1 NAME

DR::Tarantool::MsgPack::AsyncClient - async client for tarantool.

=head1 SYNOPSIS

    use DR::Tarantool::MsgPack::AsyncClient;

    DR::Tarantool::MsgPack::AsyncClient->connect(
        host => '127.0.0.1',
        port => 12345,
        spaces => $spaces,
        sub {
            my ($client) = @_;
        }
    );

    $client->insert('space_name', [1,2,3], sub { ... });


=head1 Class methods

=head2 connect

Connect to <Tarantool:http://tarantool.org>, returns (by callback) an
object which can be used to make requests.

=head3 Arguments

=over

=item host & port & user & password

Address and auth information of remote tarantool.

=item space

A hash with space description or a L<DR::Tarantool::Spaces> reference.

=item reconnect_period

An interval to wait before trying to reconnect after a fatal error
or unsuccessful connect. If the field is defined and is greater than
0, the driver tries to reconnect to the server after this interval.

Important: the driver does not reconnect after the first
unsuccessful connection. It calls callback instead.

=item reconnect_always

Try to reconnect even after the first unsuccessful connection.

=back

=cut


use DR::Tarantool::MsgPack::LLClient;
use DR::Tarantool::Spaces;
use DR::Tarantool::Tuple;
use DR::Tarantool::Constants;
use DR::Tarantool::MsgPack::AsyncClientInit;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;
use Scalar::Util ();
use Data::Dumper;

sub connect {
    my $class = shift;
    my ($cb, %opts);
    if ( @_ % 2 ) {
        $cb = pop;
        %opts = @_;
    } else {
        %opts = @_;
        $cb = delete $opts{cb};
    }

    $class->_llc->_check_cb( $cb );

    if (delete $opts{lazy}) {
        DR::Tarantool::MsgPack::AsyncClientInit->new(
            %opts, $cb
        );
        return;
    }

    my $host = $opts{host} || 'localhost';
    my $port = $opts{port} or croak "port isn't defined";

    my $user        = delete $opts{user};
    my $password    = delete $opts{password};

    my $spaces = undef;
    if ($opts{spaces}) {
        $spaces = Scalar::Util::blessed($opts{spaces}) ?
            $opts{spaces} : DR::Tarantool::Spaces->new($opts{spaces});
        $spaces->family(2);
    }

    my $reconnect_period    = $opts{reconnect_period} || 0;
    my $reconnect_always    = $opts{reconnect_always} || 0;

    my $on_callbacks        = { %{ $opts{on} || {} } };

    my $connect_timeout     = $opts{connect_timeout};
    my $connect_attempts    = $opts{connect_attempts} || 1;

    my $request_timeout     = $opts{request_timeout};


    DR::Tarantool::MsgPack::LLClient->connect(
        host                => $host,
        port                => $port,
        user                => $user,
        password            => $password,
        reconnect_period    => $reconnect_period,
        reconnect_always    => $reconnect_always,

        on                  => $on_callbacks,

        connect_timeout     => $connect_timeout,
        connect_attempts    => $connect_attempts,

        request_timeout     => $request_timeout,

        sub {
            my ($client) = @_;
            unless (ref $client) {
                $cb->($client);
                return;
            }

            my $self = bless {
                llc         => $client,
                spaces      => $spaces,
            } => ref($class) || $class;
            $self->_load_schema($cb);

            return;
        }
    );

    return;
}

{
    # LLC methods to be set for $self->_llc
    my @methods = qw/
        disconnect
        reconnect_always
        reconnect_period
        request_timeout
        connect_attempts
        connect_tries
        connect_timeout
    /;
    no strict 'refs';

    for my $method (@methods) {
        *$method = sub { shift->_llc->$method(shift) }
    }
}

sub reconnect {
    my $self = shift;
    my $cb   = shift;

    croak 'Callback must be CODEREF' unless 'CODE' eq ref $cb;

    $self->_llc->on(connfail => $cb);
    $self->_llc->{_connect_cb} = $cb;
    DR::Tarantool::LLClient::connect($self->_llc);

    return;
}

sub _load_schema {
    my ( $self, $cb, $remove_old ) = @_;

    if ( !$remove_old and $self->{spaces} ) {
        $cb->($self);
        return;
    }

    my %spaces = ();
    my ( $get_spaces_cb, $get_indexes_cb );

    # get numbers of existing non-service spaces
    $get_spaces_cb = sub {
        my ( $status, $data, $error_msg ) = @_;
        unless ( $status eq 'ok' ) {
            $cb->("cannot perform select from space '_space' to load schema: " . $error_msg);
            return;
        }
        my $next = $data;
        LOOP: {
            do {{
                last LOOP unless $next;
                my $raw = $next->raw;
                # $raw structure:
                # [space_no, uid, space_name, engine, field_count, {temporary}, [format]]

                next unless $raw->[2];     # no space name
                next if $raw->[2] =~ /^_/; # skip service spaces

                $spaces{$raw->[0]} =
                    {
                        name   => $raw->[2],
                        fields => [
                                    map { $_->{type} = uc($_->{type}) if $_->{type}; $_ }
                                        @{ ref $raw->[6] eq 'ARRAY' ? $raw->[6] : [$raw->[6]] }
                                  ],
                    }
            }} while ($next = $next->next);
        }

        DR::Tarantool::MsgPack::AsyncClient::select(
            $self,
            DR::Tarantool::Constants::get_space_no('_vindex'), 0, [],
            $get_indexes_cb,
        );
    };

    # get index structure for each of spaces we got
    $get_indexes_cb = sub {
        my ( $status, $data, $error_msg ) = @_;
        unless ( $status eq 'ok' ) {
            $cb->("cannot perform select from space '_vindex' to load schema: " . $error_msg);
            return;
        }
        my $next = $data;
        LOOP: {
            do {{
                last LOOP unless $next;
                my $raw = $next->raw;
                # $raw structure:
                # [space_no, index_no, index_name, index_type, {params}, [fields] ]

                my $space_no = $raw->[0];
                next unless exists $spaces{$space_no};

                unless ( defined($raw->[1]) and defined($raw->[2]) ) {
                    delete $spaces{$space_no};
                    next;
                }
                $spaces{$space_no}->{indexes}{$raw->[1]} =
                    {
                        name => $raw->[2],
                        fields => [ map { $_->[0] } @{ $raw->[5] } ],
                    };

                # add to fields array ones found in 'indexes'

                $spaces{$space_no}->{fields}->[ $_->[0] ]->{type} = uc( $_->[1] )
                    for @{ $raw->[5] };

            }} while ($next = $next->next);
        }

        for my $space ( keys %spaces ) {
            unless ( $spaces{$space}{fields} ) {
                delete $spaces{$space};
                next;
            }
            unless ( $spaces{$space}{indexes} ) {
                delete $spaces{$space};
                next;
            }
            for my $index ( values %{$spaces{$space}->{indexes}} ) {
                @{ $index->{fields} } =
                    map { exists $spaces{$space}{fields}[$_]{name} ? $spaces{$space}{fields}[$_]{name} : $_ }
                        @{ $index->{fields} };
            }
        }
        $self->{spaces} = DR::Tarantool::Spaces->new(\%spaces);
        $self->{spaces}->family(2); # so DR::Tarantool::Spaces::pack_field/unpack_field() not used

        $self->set_schema_id($cb);
    };

    DR::Tarantool::MsgPack::AsyncClient::select(
        $self,
        DR::Tarantool::Constants::get_space_no('_vspace'), 0, [],
        $get_spaces_cb,
    );

    return $self;
}

sub _llc { return $_[0]{llc} if ref $_[0]; 'DR::Tarantool::MsgPack::LLClient' }


sub _cb_default {
    my ($res, $s, $cb, $connect_obj, $caller_sub) = @_;
    if ($res->{status} ne 'ok') {
        my $error_name = DR::Tarantool::Constants::get_error_name($res->{CODE});

        if ( $error_name and $error_name eq 'ER_WRONG_SCHEMA_VERSION' ) {
            $connect_obj->{SCHEMA_ID} = undef;
            $connect_obj->{spaces}    = undef;
            $connect_obj->_load_schema(
                sub { $caller_sub->(shift, $caller_sub) }
            );
            return;
        }

        $cb->($res->{status} => $res->{CODE}, $res->{ERROR});
        return;
    }

    if ($s) {
        $cb->(ok => $s->tuple_class->unpack( $res->{DATA}, $s ), $res->{CODE});
        return;
    }

    unless ('ARRAY' eq ref $res->{DATA}) {
        $cb->(ok => $res->{DATA}, $res->{CODE});
        return;
    }

    unless (@{ $res->{DATA} }) {
        $cb->(ok => undef, $res->{CODE});
        return;
    }
    $cb->(ok => DR::Tarantool::Tuple->new($res->{DATA}), $res->{CODE});
    return;
}

=head1 Worker methods

All methods accept callbacks which are invoked with the following
arguments:

=over

=item status

On success, this field has value 'ok'. The value of this parameter
determines the contents of the rest of the callback arguments.

=item a tuple or tuples or an error code

On success, the second argument contains tuple(s) produced by the
request. On error, it contains the server error code.

=item errorstr

Error string in case of an error.

    sub {
        if ($_[0] eq 'ok') {
            my ($status, $tuples) = @_;
            ...
        } else {
            my ($status, $code, $errstr) = @_;
            ...
        }
    }

=back


=head2 ping

Ping the server.

    $client->ping(sub { ... });

=head2 insert, replace


Insert/replace a tuple into a space.

    $client->insert('space', [ 1, 'Vasya', 20 ], sub { ... });
    $client->replace('space', [ 2, 'Petya', 22 ], sub { ... });


=head2 call_lua

Call Lua function.

    $client->call_lua(foo => ['arg1', 'arg2'], sub {  });


=head2 select

Select a tuple (or tuples) from a space by index.

    $client->select('space_name', 'index_name', [ 'key' ], %opts, sub { .. });

Options can be:

=over

=item limit

=item offset

=item iterator

An iterator for index. Can be:

=over

=item ALL

Returns all tuples in space.

=item EQ, GE, LE, GT, LT

=back

=back


=head2 delete

Delete a tuple.

    $client->delete('space_name', [ 'key' ], sub { ... });


=head2 update

Update a tuple.

    $client->update('space', [ 'key' ], \@ops, sub { ... });

C<@ops> is array of operations to update.
Each operation is array of elements:

=head2 upsert

Upsert a tuple.

    $client->upsert('space', [ 1, 'Vasya', 'text' ], \@ops, sub { ... });

Inserts the tuple (second argument) if not exists, otherwise works as C<update> method
C<@ops> is array of operations to update if specified tuple exists.
Each operation is array of elements:


=over

=item code

Code of operation: C<=>, C<+>, C<->, C<&>, C<|>, etc

=item field

Field number or name.

=item arguments

=back

=cut


sub set_schema_id {
    my $self = shift;
    my $cb = pop;

    $self->_llc->_check_cb( $cb );
    $self->_llc->ping(
        sub {
            my ( $res ) = @_;
            if ($res->{status} ne 'ok') {
                $cb->( 'cannot perform ping in order to get schema_id '
                    . "status=$res->{status}, code=$res->{CODE}, error=$res->{ERROR}" );
                return;
            }

            $self->{SCHEMA_ID} = $res->{SCHEMA_ID};
            $cb->($self);
            return;
    });
}

sub ping {
    my $self = shift;
    my $cb = pop;

    $self->_llc->_check_cb( $cb );
    $self->_llc->ping(sub { _cb_default($_[0], undef, $cb, $self) });
}

sub insert {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $tuple = shift;
    $self->_llc->_check_tuple( $tuple );


    my $sno;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->insert(
            $sno,
            $tuple,
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number,
            $tuple = $s->pack_tuple( $tuple );
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number,
                 $tuple = $s->pack_tuple( $tuple );

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }

    $subref->($self, $subref);
    return;
}

sub replace {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $tuple = shift;
    $self->_llc->_check_tuple( $tuple );


    my $sno;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->replace(
            $sno,
            $tuple,
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number,
            $tuple = $s->pack_tuple( $tuple );
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number,
                 $tuple = $s->pack_tuple( $tuple );

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }

    $subref->($self, $subref);
    return;
}

sub delete :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    
    my $space = shift;
    my $key = shift;


    my $sno;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->delete(
            $sno,
            $key,
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number,
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number,

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }

    $subref->($self, $subref);
    return;
}

sub select :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $index = shift;
    my $key = shift;
    my %opts = @_;

    my $sno;
    my $ino;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->select(
            $sno,
            $ino,
            $key,
            $opts{limit},
            $opts{offset},
            $opts{iterator},
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
        croak 'If space is number, index must be number too'
            unless Scalar::Util::looks_like_number $index;
        $ino = $index;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number;
            $ino = $s->_index( $index )->{no};
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number;
                 $ino = $s->_index( $index )->{no};

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }
    $subref->($self, $subref);
    return;
}

sub update :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $key = shift;
    my $ops = shift;

    my $sno;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->update(
            $sno,
            $key,
            $ops,
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number;
            $ops = $s->pack_operations($ops);
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number;
                 $ops = $s->pack_operations($ops);

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }

    $subref->($self, $subref);
    return;
}

sub upsert :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $tuple = shift;
    my $ops = shift;

    my $sno;
    my $s;

    my $subref = sub {
        my $self        = shift;
        my $subref_self = shift;
        $self->_llc->upsert(
            $sno,
            $tuple,
            $ops,
            $self->{SCHEMA_ID},
            sub {
                my ($res) = @_;
                _cb_default($res, $s, $cb, $self, $subref_self);
            }
        );
    };

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    }
    else {
        eval {
            $s = $self->{spaces}->space($space);
            $sno = $s->number;
            $ops = $s->pack_operations($ops);
        };
        if ($@) {
            $self->_load_schema(
            sub {
                 my $self = shift;
                 $s = $self->{spaces}->space($space);
                 $sno = $s->number;
                 $ops = $s->pack_operations($ops);

                 $subref->($self, $subref);
                 return;
            } => 'remove old');
            return;
        }
    }

    $subref->($self, $subref);
    return;
}

sub call_lua {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );

    my $proc = shift;
    my $tuple = shift;

    $tuple = [ $tuple ] unless ref $tuple;
    $self->_llc->_check_tuple( $tuple );


    $self->_llc->call_lua(
        $proc,
        $tuple,
        sub {
            my ($res) = @_;
            _cb_default($res, undef, $cb, $self);
        }
    );
    return;
}


sub last_code { $_[0]->_llc->last_code }


sub last_error_string { $_[0]->_llc->last_error_string }

1;
