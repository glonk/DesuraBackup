#!/usr/bin/perl
require 5.12.0;     # might run on 5.10 too

BEGIN {
    # if there is a local directory "extlib" put it into INC
    if ( -d "extlib" ) {
        use local::lib 'extlib';
    }
}

use constant VERSION => 0.26.4;
use constant BUILD => 4;
use constant OVERRIDE_SIZECHECK => false;

use Modern::Perl;
use autodie;

#use IO::File;

## login-via-file

use YAML;
use YAML::Any;
use Data::Dumper;

my $login_file = "login.yml";
#my @desura_hosts = ( "http://api.desura.com", "ips...." );
#my %config = (
#    host => $desura_hosts[0]
#);

if ( ! -e $login_file ) {
    print("!!! Require to have login data present in $login_file");
    exit();
}

my ($login) = YAML::Any::LoadFile( $login_file );
#print Dumper( $login );

## Login 2 Desura

#IO::Socket::SSL # http://search.cpan.org/perldoc?IO%3A%3ASocket%3A%3ASSL
use HTTP::Tiny;
use HTTP::Tiny::Multipart;
use HTTP::CookieJar;
use File::Slurp;

my $jar = HTTP::CookieJar->new;

if ( -e "cookies.yml" ) {
    say( 'found & loading cookies' );
    $jar->load_cookies( YAML::Any::LoadFile( "cookies.yml" ) );
}

my $http = HTTP::Tiny->new(
    agent => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:38.9) Gecko/20100101 Goanna/2.0 Firefox/38.9 PaleMoon/26.1.1',
    cookie_jar => $jar,
    timeout => 30
);

#"masterchief" ~~
#print( Dumper( scalar $jar->cookies_for("http://desura.com") ));

if ( scalar $jar->cookies_for("http://desura.com") > 0 ) {
    say 'cookies ok (assuming logged in state)';
} else {
    my $response = $http->post_multipart( 'http://api.desura.com/3/memberlogin', {
        username => $login->{username},
        password => $login->{password}
    });

    #my $response = $http->request('POST', 'http://www.desura.com/members/login', {
    #    content => "username=".$login->{username}."&password=".$login->{password}
    #});

    if ( $response->{success} ) {
        #print $response->{content};
        say("login ok");
        write_file( "memberlogin.xml", $response->{content} ) ;
    } else {
        print $response->{status}, $response->{content};
        exit();
    }
}

#print Dumper( $fresh_jar->cookies_for("http://desura.com") );
say("saving cookies");
YAML::Any::DumpFile( "cookies.yml", $jar->dump_cookies() );

## do work

#my @games;
my %games;
my @items;

say "scanning account...";
my $response = $http->get( 'http://api.desura.com/1/memberdata' );
die "no memberlist" if ( !$response->{success} || length $response->{content} == 0 );

#print $response->{content};

write_file( "memberdata0.xml", $response->{content} ) ;

use XML::Twig;

my $xml = XML::Twig->new(
    twig_handlers => {
        #'status' => sub { $_->print }           # print it
        'memberdata/games/game' => sub {
            my $game = {};
            $game->{'id'} = $_->{'att'}->{'siteareaid'};
            $game->{'name'} = $_->first_child('name') ? $_->first_child('name')->text : "undef";
            $game->{'nameid'} = $_->first_child('nameid') ? $_->first_child('nameid')->text : "undef";
            $game->{'downloadable'} = $_->first_child('downloadable') ? $_->first_child('downloadable')->text : "undef";
            #push( @games, $game );
            $games{ $game->{'id'} } = $game;
        },
        'memberdata/platforms/platform/games/game' => sub {
            my $branches = $_->first_child('branches');
            my @branchlist = $branches->children('branch');

            #my $branch = $branches->first_child('branch');
            foreach  my $branch ( @branchlist ) {
                my $item = {};
                $item->{'id'} = $_->{'att'}->{'siteareaid'};

                if ( !defined $branch->{'att'}->{'id'} ) {
                    say "found dubious branch without id - skipping it!";
                    $_->print;
                    return;
                }

                $item->{'branchid'} = $branch->{'att'}->{'id'};
                #say $item->{'id'} . "/" . $item->{'branchid'};
                $item->{'branchplatform'} = $branch->{'att'}->{'platformid'};
                $item->{'branchname'} = $branch->first_child('name') ? $branch->first_child('name')->text : "unknown";
                $item->{'filesize'} = $branch->first_child('mcf') ? $branch->first_child('mcf')->first_child('filesize')->text : -1;
                $item->{'onaccount'} = $branch->first_child('onaccount') ? $branch->first_child('onaccount')->text : 0;
                push( @items, $item );
            }
        },
      },
    pretty_print => 'indented',                 # output will be nicely formatted
);

# parse memberdata xml and build games list
$xml->parse( $response->{content} );

my $statuscode = $xml->root->first_child('status')->{'att'}->{'code'};
say "deauthed - restart please" if $statuscode == 104;
unlink "cookies.yml" if $statuscode == 104;
die "status: " . $statuscode if ( $statuscode != 0 );

say "writing memberlist";
write_file( "memberdata.xml", $response->{content} ) ;

#print Dumper( $response->{content} );
#print Dumper( %games );

die "couldn't find any games on account" if ( scalar keys %games <= 0 );
say "found " . (scalar keys %games) . " games on account";

# write it to disk

YAML::Any::DumpFile( "games.yml", \%games );
YAML::Any::DumpFile( "items.yml", \@items );

use URI;
use URI::Escape;
use File::Path qw(make_path);

my $basepath;

## work with the list of games
foreach my $item ( @items ) {
    say( "working on " . $games{ $item->{id} }->{name} . " [".$item->{id}."/".$item->{branchplatform}."]" );

    my $gamename = defined $games{ $item->{id} } && defined $games{ $item->{id} }->{nameid} ? $games{ $item->{id} }->{nameid} : "unnamed";
    $basepath = "downloads/" . $item->{id} . "-" . $gamename;
    make_path( $basepath );

    if ( !$games{ $item->{id} }->{downloadable} || !$item->{onaccount} ) {
        say( "desura says this content [".$item->{branchname}."] is not owned by you / is not downloadable! skipping!");
        next;
    }

    my $mcf_file = $basepath . "/" . $item->{'branchid'} . "-" . $item->{'branchplatform'} . ".mcf";
    if ( -e $mcf_file ) {
        if ( OVERRIDE_SIZECHECK ) {
            say 'file exists and checks are overriden... skipping!';
            next;
        }

        my $size = -s $mcf_file;
        if ( $size eq $item->{filesize} ) {
            say "found and skipping existing MCF-file";
            next;
        } else {
            say "found existant but possibly incomplete or updated MCF-file -> overwriting";
        }
    }

    my $response = $http->post_multipart( 'http://api.desura.com/2/itemdownloadurl', {
        sitearea => "games",
        siteareaid => $item->{id},
        branch => $item->{branchid},
    });

    write_file( $basepath . "/item".$item->{branchid}."-".$item->{branchplatform} .".xml", $response->{content} ) ;

    if ( !$response->{success} || length $response->{content} == 0 ) {
        warn "no auth for ".$item->{id}. " [".$response->{content}."] -> postphoning it";
        push( @items, $item );
        sleep(10);
        next;
    }

    $xml->parse( $response->{content} );
    my $statuscode = $xml->root->first_child('status')->{'att'}->{'code'};

    if ( $statuscode == 0 ) {
        $item->{'link'} = $xml->root->first_child('item')->first_child('mcf')->first_child('urls')->first_child('url')->first_child('link')->text;
        $item->{'branchname'} = $xml->root->first_child('item')->first_child('name')->text;

        say("downloading MCF...");
        downloadMCF( $item->{'link'}, $item );
    } else {
        say "gotten an api error: $statuscode -> skipping it";
        #push( @items, $item );
        #sleep(10);
        #next;
    }

    # prevent overloading server
    sleep(10);
}

#YAML::Any::DumpFile( "urls.yml", \@urls );
YAML::Any::DumpFile( "final.yml", \@items );

sub downloadMCF {
    my ($link, $item) = @_;
    die( 'too few arguments to downloadMCF' ) if @_ < 2;

    my $u = URI->new( $item->{'link'} );
    $u->fragment( uri_escape( $u->fragment ) );

    #say "base: $basepath";
    #say Dumper( $item );

    my $response = $http->mirror( $u->as_string,  $basepath . "/" . $item->{'branchid'} . "-" . $item->{'branchplatform'} . ".mcf", {});

    if ( $response->{success} ) {
        my $size = -s $basepath . "/" . $item->{'branchid'} . "-" . $item->{'branchplatform'} . ".mcf";

        if ( $size eq $item->{filesize} ) {
            say "download ok!";
        } else {
            say "downloaded file sizes mismatch!";
        }
    } else {
        print $response->{status};
    }
}
