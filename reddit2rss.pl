#!/usr/bin/perl -w

use strict;
use utf8::all;
use AnyEvent;
use Reddit::Client;
use DBI;
use YAML::Tiny;
use XML::FeedPP;
use Text::Unidecode;
use Date::Parse;
use Date::Format;
use Data::Dumper;
use Encode;
use JSON::XS;
use FindBin qw( $Bin );

my $configpath = "$Bin/config.yml";

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

my $interval = int($config->{interval});
my $json = JSON::XS->new->utf8;

my $f = AnyEvent->timer(after=>0, interval=>$interval, cb=> sub {
  my $newposts = 0;
  foreach my $sub(keys %allsubs){
    my $posts = $r->fetch_links(subreddit=>$sub, limit=>40);
    foreach my $post(@$posts){
      foreach my $feed(keys %{$config->{subs}}){
        if(!exists $config->{subs}->{$feed}->{$post->{subreddit}}){ next; }

        if(!$post->{is_self} && $post->{score} >= $config->{subs}->{$feed}->{$post->{subreddit}}){
          my $url = $post->{url};
          my $id = $post->{id};

          my $exists = $dbh->selectrow_arrayref('SELECT id FROM links WHERE guid=? OR url=?', undef, $id, $url);
          if(!defined $exists){
            my $safeurl = quotemeta($url);
            my $page = encode('utf8', `curl --referer https://www.google.com/ -A "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)" -sL $safeurl | unfluff`);
            my $pagedata = $json->decode($page);
            my $subreddit = $post->{subreddit};
            my $author = length($pagedata->{author}) > 0 ? unidecode($pagedata->{author}[0]) : undef;
            my $domain = $post->{domain};
            my $title = unidecode($post->{title});
            my $image = $pagedata->{image} ? $pagedata->{image} : $post->{thumbnail};
            my $content = $pagedata->{text} ne '' ? unidecode($pagedata->{text}) : undef;
            my $comments = "https://reddit.com$post->{permalink}";

            $newposts++;
            print "$feed: $title ($domain [$subreddit])\n";
            $dbh->do('INSERT INTO links (feed, subreddit, guid, title, domain, author, url, comments, image, content, published) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)', undef, $feed, $subreddit, $id, $title, $domain, $author, $url, $comments, $image, $content);
          }
        }
      }
    }
    sleep 2; # need to keep it under 30 api calls per minute
  }

  if($newposts){
    foreach my $feed(keys %{$config->{subs}}){
      print "Generating feed $feed...\n";
      my $rss = XML::FeedPP::RSS->new(version => '2.0');
      $rss->title(ucfirst($feed));
      $rss->language('en');
      $rss->xmlns('xmlns:dc' => 'http://purl.org/dc/elements/1.1/');
      my $posts = $dbh->selectall_arrayref('SELECT subreddit, guid, title, domain, author, url, comments, image, content, published FROM links WHERE feed=? ORDER BY published DESC LIMIT 20', undef, $feed);

      foreach my $post(@$posts){
        my $text = $post->[8] ? $post->[8] : '';
        my $description = <<EOF;
<image src="$post->[7]"/>

$text
EOF
        $description =~ s/\n/<br\/>/g;
        my $item = $rss->add_item($post->[5]);
        $item->guid($post->[1], isPermaLink => 'false');
        $item->title($post->[2]);
        $item->set('dc:creator', "$post->[3] [$post->[0]]");
        $item->set('comments', $post->[6]);
        $item->pubDate(time2str('%a, %d %b %Y %X %Z', str2time($post->[9])));
        $item->description($description);
      }

      my $path = "$config->{outdir}/$feed.xml";
      $rss->to_file($path);
    }
  }
});

AnyEvent->condvar->recv;
