#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::TempDir;

use Path::Class;

use ok 'Search::GIN::Driver::BerkeleyDB';

{
    package Drv;
    use Moose;

    with (
        'Search::GIN::Driver::BerkeleyDB',
        'Search::GIN::Driver::Pack::Length' => {
            alias => {
                pack_length => "pack_values",
                unpack_length => "unpack_values",
            },
        },
    );
}

my $d = Drv->new( home => temp_root );

my $id = "a" x 16;
my @ids = map { $id++ } 1 .. 10;

my @foo = @ids[3,4,6];
my @bar = @ids[4,8];

$d->insert_entry( undef, $_ => "foo" ) for @ids[3,6];
$d->insert_entry( undef, $ids[8] => "bar" );
$d->insert_entry( undef, $ids[4] => qw(foo bar) );

is_deeply( [ sort $d->fetch_entry(undef, 'foo')->all ], [ sort @foo ], "foo entry" );
is_deeply( [ sort $d->fetch_entry(undef, 'bar')->all ], [ sort @bar ], "bar entry" );

$d->insert_entry(undef, $ids[1] => qw(foo));
$d->insert_entry(undef, $ids[2] => qw(foo));

is_deeply( [ sort $d->fetch_entry(undef, 'foo')->all ], [ sort @foo, @ids[1,2] ], "merged" );

my $txn = $d->txn_begin;

$d->insert_entry(undef, $ids[5] => qw(quxx));

is_deeply( [ $d->fetch_entry(undef, 'quxx')->all ], [ $ids[5] ], "mid txn" );

$d->txn_commit($txn);

is_deeply( [ $d->fetch_entry(undef, 'quxx')->all ], [ $ids[5] ], "txn succeeded" );

eval {
    $d->txn_do(sub {
        $d->insert_entry( undef, $ids[0] => qw(gorch) );

        is_deeply( [ $d->fetch_entry(undef, "gorch")->all ], [ $ids[0] ], "mid txn" );

        die "user error";
    });
};

like( $@, qr/user error/, "got error" );

{
    is_deeply( [ $d->fetch_entry(undef, "gorch")->all ], [ ], "transaction aborted" );
}

$d->txn_do(sub {
    $d->insert_entry( undef, $ids[5] => qw(zot) );
});

is_deeply( [ $d->fetch_entry(undef, "zot")->all ], [ $ids[5] ], "transaction succeeded" );

$d->remove_ids(undef, @ids[2,4]);

is_deeply( [ sort $d->fetch_entry(undef, 'foo')->all ], [ sort @ids[1, 3, 6] ], "removed" );


