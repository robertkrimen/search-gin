#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::TempDir;

use Set::Object;

{
    # this will be a default class, for now I'm keeping them separate
    package MyGIN;
    use Moose;

    # in memory index:
    #with qw(
    #   Search::GIN::DelegateToIndexed
    #   Search::GIN::Driver::Hash
    #);

    # on disk index:
    with (
        qw(
            Search::GIN::DelegateToIndexed
            Search::GIN::Driver::BerkeleyDB
        ),
        'Search::GIN::Driver::Pack::Length' => {
            alias => {
                pack_length   => "pack_values",
                unpack_length => "unpack_values",
            }
        },
    );

    # DelegateToIndexed means we delegate everything to Query and Indexable
    # there's also Callbacks, and presumably custom impls

    # PackUUID is because BerkeleyDB is ondisk
    # it's an implementation of pack_ids and unpack_ids that uses unpack/pack
    # on constant width strings

    # the only required method left after all these roles were added
    # we fake it here, but it should go to the storage backend
    sub ids_to_objects {
        my ( $self, $c, @ids ) = @_;
        @{ $self->objects }{@ids};
    }

    around objects_to_ids => sub {
        my ( $next, $self, $c, @objs ) = @_;
        my @ids = $self->$next($c, @objs);
        @{ $self->objects }{@ids} = @objs;
        return @ids;
    };

    has objects => (
        isa => "HashRef",
        is  => "rw",
        default => sub { {} },
    );

    # you create the query objects, the GIN implementation uses them
    # consistently with the index
    package MyTagQuery;
    use Moose::Role;

    use MooseX::Types::Set::Object;

    with qw(Search::GIN::Query);

    has tags => (
        isa => "Set::Object",
        is  => "ro",
        coerce   => 1,
        required => 1,
    );

    sub extract_values {
        my $self = shift;
        return (
            values => [ $self->tags->members ],
        );
    }

    package MyTagQuery::Intersection;
    use Moose;

    with qw(MyTagQuery);

    sub consistent {
        my ( $self, $index, $c, $item ) = @_;
        return $self->tags->subset($item->tags);
    }

    around extract_values => sub {
        my ( $next, $self, @args ) = @_;
        return (
            method => "all",
            $self->$next(@args),
        );
    };

    __PACKAGE__->meta->make_immutable;

    package MyTagQuery::Union;
    use Moose;

    with qw(MyTagQuery);

    sub consistent {
        my ( $self, $index, $c, $item ) = @_;
        return $self->tags->intersection($item->tags)->size >= 1;
    }

    __PACKAGE__->meta->make_immutable;

    # this is an indexable object
    package MyObject;
    use Moose;

    use overload '""' => sub { $_[0]->id }, fallback => 1; # is_deeply diagnosis

    use MooseX::Types::Set::Object;

    with qw(Search::GIN::Indexable);

    has id => (
        isa => "Str",
        is  => "ro",
    );

    sub gin_id { shift->id }

    has tags => (
        isa => "Set::Object",
        is  => "ro",
        coerce  => 1,
        default => sub { Set::Object->new },
    );

    sub gin_extract_values {
        my $self = shift;
        $self->tags->members;
    }

    __PACKAGE__->meta->make_immutable;
}


my $gin = MyGIN->new(
    home => temp_root,
    file => "foo.idx",
    distinct => 1,
);

my @objs = map { MyObject->new(%$_) } (
    {
        id   => "aaaaaaaaaaaaaaaa",
        tags => [ qw(foo bar baz donkey) ],
    },
    {
        id   => "aaaaaaaaaaaaaaab",
        tags => [ qw(bar gorch baz) ],
    },
    {
        id   => "aaaaaaaaaaaaaaac",
        tags => [ qw(zot urf donkey gorch) ],
    },
);

$gin->insert(undef, @objs);

{
    my @res = $gin->query( undef, MyTagQuery::Intersection->new( tags => [qw(foo)] ) )->all;
    is_deeply( [ @res ], [ $objs[0] ] );
}

{
    my @res = $gin->query( undef, MyTagQuery::Union->new( tags => [qw(foo)] ) )->all;
    is_deeply( [ @res ], [ $objs[0] ] );
}

{
    my @res = $gin->query( undef, MyTagQuery::Intersection->new( tags => [qw(bar)] ) )->all;
    is_deeply( [ sort @res ], [ sort @objs[0, 1] ] );
}

{
    my @res = $gin->query( undef, MyTagQuery::Intersection->new( tags => [qw(gorch)] ) )->all;
    is_deeply( [ sort @res ], [ sort @objs[1, 2] ] );
}

{
    my @res = $gin->query( undef, MyTagQuery::Intersection->new( tags => [qw(bar gorch)] ) )->all;
    is_deeply( [ @res ], [ $objs[1] ] );
}

{
    my @res = $gin->query( undef, MyTagQuery::Union->new( tags => [qw(bar gorch)] ) )->all;
    is_deeply( [ sort @res ], [ sort @objs ] );
}

