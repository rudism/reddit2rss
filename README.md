# Reddit2RSS

You can use this to generate RSS feeds from multireddits, including only posts that meet a certain popularity threshold.

## Setup

Create the database:

```sh
$ sqlite3 data.db < schema.sql
```

You will need to [create a new application on Reddit](https://www.reddit.com/prefs/apps) in order to get a client key and secret. Then create your config file and edit it appropriately:

```sh
$ cp config.yml.example config.yml
$ vim config.yml
```

- `interval` is how often in seconds you want to poll the Reddit API for new posts
- `db` is the path to the sqlite database you created from the schema
- `outdir` is the path to the directory where you want the RSS files saved
- `feedurl` is the url that will be used for the RSS files
- `feedemail` will be used as the feed and author email address in the RSS files
- the `reddit` section contains your Reddit API keys and credentials
- the `subs` section defines the subreddits and thresholds for the RSS feeds you want to generate

## Feed Configuration

```yml
subs:
  feedname1:
    subreddit1: 10
    subreddit2: 5
  feedname2:
    subreddit1: 20
    subreddit3: 2
```

The above config would cause two feeds to be generated. `feedname1.xml` will contain all posts in `subreddit1` that break into the top 10 at any point, and all posts in `subreddit2` that break into the top 5 posts. `feedname2.xml` will contain all posts in `subreddit1` that meet or break into the top 20, and all posts in `subreddit3` that break into the top 2. You can create as many feeds as you like in this manner. The maximum threshold limit you can set is 100.

## Running

The script runs as a daemon that polls Reddit periodically and regenerates the feeds whenever new posts meet the specified thresholds. I recommend using a process manager such as [pm2](http://pm2.keymetrics.io/).

```sh
$ pm2 start --name reddit2rss --interpreter /usr/bin/perl /path/to/reddit2rss.pl
```

You will need to output the RSS files to a path that is already accessible via the web in order to access them, of course. You can optionally use something like [rss-to-full-rss](https://www.npmjs.com/package/rss-fulltext) to inject the actual article content into the feeds as well.
