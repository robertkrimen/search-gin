#!/usr/bin/perl

package Search::GIN::ExpandKeys;
use Moose::Role;

sub expand_keys {
    my ( $self, @keys ) = @_;
    return map { $self->expand_key($_) } @keys;
}

sub expand_key {
    my ( $self, $value, %args ) = @_;

    return $self->expand_key_string($value) if not ref $value;

    my $method = "expand_keys_" . lc ref($value);

    return $self->$method($value);
}

sub expand_key_prepend {
    my ( $self, $prefix, @keys ) = @_;
    return map { [ $prefix, @$_ ] } @keys;
}

sub expand_key_string {
    my ( $self, $str ) = @_;
    return [ $str ];
}

sub expand_keys_array {
    my ( $self, $array ) = @_;
    return map { $self->expand_key($_) } @$array;
}

sub expand_keys_hash {
    my ( $self, $hash ) = @_;

    return map {
        $self->expand_key_prepend(
            $_,
            $self->expand_key($hash->{$_})
        );
    } keys %$hash;
}

__PACKAGE__

__END__

=pod

=head1 NAME

Search::GIN::ExpandKeys - 

=head1 SYNOPSIS

	use Search::GIN::ExpandKeys;

=head1 DESCRIPTION

=cut


