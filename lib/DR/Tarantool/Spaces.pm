use utf8;
use strict;
use warnings;

package DR::Tarantool::Spaces;
use Carp;
# $Carp::Internal{ (__PACKAGE__) }++;

=head1 NAME

DR::Tarantool::Spaces - spaces container

=head1 SYNOPSIS

    my $s = new DR::Tarantool::Spaces({
            1   => {
                name            => 'users',         # space name
                default_type    => 'STR',           # undescribed fields
                fields  => [
                    qw(login password role),
                    {
                        name    => 'counter',
                        type    => 'NUM'
                    },
                    {
                        name    => 'something',
                        type    => 'UTF8STR',
                    }
                ],
                indexes => {
                    0   => 'login',
                    1   => [ qw(login password) ],
                }
            },

            0 => {
                ...
            }
    });

    my $f = $s->pack_field('users', 'counter', 10);
    my $f = $s->pack_field('users', 1, 10);             # the same
    my $f = $s->pack_field(1, 1, 10);                   # the same


=cut

sub new {
    my ($class, $spaces) = @_;
    croak 'spaces must be a HASHREF' unless 'HASH' eq ref $spaces;
    croak "'spaces' is empty" unless %$spaces;

    my (%spaces, %fast);
    for (keys %$spaces) {
        my $s = new DR::Tarantool::Space($_ => $spaces->{ $_ });
        $spaces{ $s->name } = $s;
        $fast{ $_ } = $s->name;
    }

    return bless {
        spaces  => \%spaces,
        fast    => \%fast,
    } => ref($class) || $class;
}

sub space {
    my ($self, $space) = @_;
    croak 'space name or number is not defined' unless defined $space;
    if ($space =~ /^\d+$/) {
        croak "space '$space' is not defined"
            unless exists $self->{fast}{$space};
        return $self->{spaces}{ $self->{fast}{$space} };
    }
    croak "space '$space' is not defined"
        unless exists $self->{spaces}{$space};
    return $self->{spaces}{$space};
}

sub pack_field {
    my ($self, $space, $field, $value) = @_;
    croak q{Usage: $spaces->pack_field('space', 'field', $value)}
        unless @_ == 4;
    return $self->space($space)->pack_field($field => $value);
}

sub unpack_field {
    my ($self, $space, $field, $value) = @_;
    croak q{Usage: $spaces->unpack_field('space', 'field', $value)}
        unless @_ == 4;

    return $self->space($space)->unpack_field($field => $value);
}

sub pack_tuple {
    my ($self, $space, $tuple) = @_;
    croak q{Usage: $spaces->pack_tuple('space', $tuple)} unless @_ == 3;
    return $self->space($space)->pack_tuple( $tuple );
}

sub unpack_tuple {
    my ($self, $space, $tuple) = @_;
    croak q{Usage: $spaces->unpack_tuple('space', $tuple)} unless @_ == 3;
    return $self->space($space)->unpack_tuple( $tuple );
}

package DR::Tarantool::Space;
use Carp;

sub new {
    my ($class, $no, $space) = @_;
    croak 'space number must conform the regexp qr{^\d+}' unless $no ~~ /^\d+$/;
    croak "'fields' not defined in space hash"
        unless 'ARRAY' eq ref $space->{fields};
    croak "'indexes' not defined in space hash"
        unless  'HASH' eq ref $space->{indexes};

    my $name = $space->{name};
    croak 'wrong space name: ' . ($name // 'undef')
        unless $name and $name =~ /^[a-z_]\w*$/i;


    my (@fields, %fast, $default_type);
    $default_type = $space->{default_type} || 'STR';
    croak "wrong 'default_type'"
        unless $default_type =~ /^(?:STR|NUM|NUM64|UTF8STR)$/;

    for (my $no = 0; $no < @{ $space->{fields} }; $no++) {
        my $f = $space->{ fields }[ $no ];

        if (ref $f eq 'HASH') {
            push @fields => {
                name    => $f->{name},
                idx     => $no,
                type    => $f->{type}
            };
        } elsif(ref $f) {
            croak 'wrong field name or description';
        } else {
            push @fields => {
                name    => $f,
                idx     => $no,
                type    => $default_type,
            }
        }

        my $s = $fields[ -1 ];
        croak 'unknown field type: ' . ($s->{type} // 'undef')
            unless $s->{type} and $s->{type} =~ /^(?:STR|NUM|NUM64|UTF8STR)$/;

        croak 'wrong field name: ' . ($s->{name} // 'undef')
            unless $s->{name} and $s->{name} =~ /^[a-z_]\w*$/i;

        $fast{ $s->{name} } = $no;
    }

    bless {
        fields          => \@fields,
        fast            => \%fast,
        name            => $name,
        number          => $no,
        default_type    => $default_type,
    } => ref($class) || $class;

}

sub name { $_[0]{name} }
sub number { $_[0]{number} }

sub _field {
    my ($self, $field) = @_;

    croak 'field name or number is not defined' unless defined $field;
    if ($field =~ /^\d+$/) {
        return $self->{fields}[ $field ] if $field < @{ $self->{fields} };
        return undef;
    }
    croak "field with name '$field' is not defined in this space"
        unless exists $self->{fast}{$field};
    return $self->{fields}[ $self->{fast}{$field} ];
}

sub pack_field {
    my ($self, $field, $value) = @_;
    croak q{Usage: $space->pack_field('field', $value)}
        unless @_ == 3;

    my $f = $self->_field($field);

    my $type = $f ? $f->{type} : $self->{default_type};

    my $v = $value;
    utf8::encode( $v ) if utf8::is_utf8( $v );
    return $v if $type eq 'STR' or $type eq 'UTF8STR';
    return pack 'L<' => $v if $type eq 'NUM';
    return pack 'Q<' => $v if $type eq 'NUM64';
    croak 'Unknown field type:' . $type;
}

sub unpack_field {
    my ($self, $field, $value) = @_;
    croak q{Usage: $space->pack_field('field', $value)}
        unless @_ == 3;

    my $f = $self->_field($field);

    my $type = $f ? $f->{type} : $self->{default_type};

    my $v = $value;
    utf8::encode( $v ) if utf8::is_utf8( $v );
    $v = unpack 'L<' => $v  if $type eq 'NUM';
    $v = unpack 'Q<' => $v  if $type eq 'NUM64';
    utf8::decode( $v )      if $type eq 'UTF8STR';
    return $v;
}

sub pack_tuple {
    my ($self, $tuple) = @_;
    croak 'tuple must be ARRAYREF' unless 'ARRAY' eq ref $tuple;
    my @res;
    for (my $i = 0; $i < @$tuple; $i++) {
        push @res => $self->pack_field($i, $tuple->[ $i ]);
    }
    return \@res;
}

sub unpack_tuple {
    my ($self, $tuple) = @_;
    croak 'tuple must be ARRAYREF' unless 'ARRAY' eq ref $tuple;
    my @res;
    for (my $i = 0; $i < @$tuple; $i++) {
        push @res => $self->unpack_field($i, $tuple->[ $i ]);
    }
    return \@res;
}

1;
