#!/usr/bin/perl -w

use strict;
use utf8::all;
use AnyEvent;
use Reddit::Client;
use DBI;
use YAML::Tiny;
use XML::RSS;
use Text::Unidecode;
use FindBin qw( $Bin );

my $configpath = "$Bin/config.yml";

print "$configpath\n";

my $config = @{YAML::Tiny->read($configpath)}[0];

my $r = new Reddit::Client(
  user_agent=>'reddit2rss.pl/1.0 by /u/rudism'
);

my $dbpath = $config->{db};
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbpath", '', '');

$r->get_token(
  client_id=>$config->{reddit}->{client_id},
  secret=>$config->{reddit}->{secret},
  username=>$config->{reddit}->{username},
  password=>$config->{reddit}->{password}
);

my %allsubs = ();
foreach my $feed(keys %{$config->{subs}}){
  foreach my $sub(keys %{$config->{subs}->{$feed}}){
    $allsubs{$sub} = 1;
  }
}

my $f = AnyEvent->timer(after=>0, interval=>$config->{interval}, cb=> sub {
  my $newposts = 0;
  foreach my $sub(keys %allsubs){
    my $posts = $r->fetch_links(subreddit=>$sub, limit=>40);
    foreach my $post(@$posts){
      foreach my $feed(keys %{$config->{subs}}){
        if(!exists $config->{subs}->{$feed}->{$post->{subreddit}}){ next; }

        if(!$post->{is_self} && $post->{score} >= $config->{subs}->{$feed}->{$post->{subreddit}}){
          my $id = $post->{id};
          my $subreddit = $post->{subreddit};
          my $domain = $post->{domain};
          my $title = unidecode($post->{title});
          my $url = $post->{url};
          my $comments = "https://reddit.com$post->{permalink}";

          my $exists = $dbh->selectrow_arrayref('SELECT id FROM links WHERE guid=? OR url=?', undef, $id, $url);
          if(!defined $exists){
            $newposts++;
            print "$feed: $title ($domain [$subreddit])\n";
            $dbh->do('INSERT INTO links (feed, guid, title, author, url, comments, published) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)', undef, $feed, $id, $title, "$domain [$subreddit]", $url, $comments);
          }
        }
      }
    }
    sleep 2; # need to keep it under 30 api calls per minute
  }

  if($newposts){
    foreach my $feed(keys %{$config->{subs}}){
      print "Generating feed $feed...\n";
      my $rss = XML::RSS->new(version => '2.0');
      $rss->channel(
        title => ucfirst($feed),
        language => 'en'
      );
      my $posts = $dbh->selectall_arrayref('SELECT guid, title, author, url, comments, published FROM links WHERE feed=? ORDER BY published DESC LIMIT 20', undef, $feed);

      foreach my $post(@$posts){
        $rss->add_item(
          guid => $post->[0],
          title => $post->[1],
          author => "$config->{feedemail} ($post->[2])",
          link => $post->[3],
          comments => $post->[4],
          pubDate => $post->[5]
        );
      }

      my $path = "$config->{outdir}/$feed.xml";
      $rss->save($path);
    }
  }
});

AnyEvent->condvar->recv;
