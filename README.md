# download_grok
 
This is a small Ruby script that logs into your twitter session with your own cookies, walks your grok conversation history and downloads every attached image that it can find.
 
The implementation is intentionally plain. It hits two graphql endpoints, uses sqlite as a simple response cache and keeps going page by page until history is exhausted. If something weird happens, it drops into pry because real debugging beats theory when an api response goes sideways.
 
You will need Ruby, bundler and a cookie file named like `config/cookie_<username>.txt`. That file should contain your `auth_token`, `ct0`, and `twid` values (one per line), the script stitches them into a cookie header and sends requests as your authenticated session.
 
Run it like this:

```
bundle install
mkdir -p images config data
bundle exec ruby download.rb -u username
```

If you omit `-u/--user`, it uses `default` and looks for `config/cookie_default.txt`. By default the cache partition is the current local date in `YYYY-MM-DD` format, which means cached API responses are reused only within that day. If you want a longer-lived cache while iterating, pass a named partition (for example `--partition dev`).
If you want to run the same process for every local cookie file, use `--all`; it scans for `config/cookie_*.txt` and runs once per discovered username.

By default it runs incrementally: it compares each conversation response against the most recent cached response for that same request URL across all partitions and stops at the first unchanged one. If you want a full pass, use `--force`.

Responses are still stored in `data/cache_<username>.sqlite`, but they are now partitioned inside that database. Delete rows from that cache if you want to force a refetch for a specific url, delete the file if you want a full clean run, or switch partitions if you want an isolated cache namespace.

Downloaded images are also tracked in a shared `data/downloaded_images.sqlite` ledger. Every downloaded file gets a row with user, timestamp, source URL, path, size, md5 and dedupe status (`unique`, `duplicate_keep`, `duplicate_delete`).

To remove one partition without touching others, run `bundle exec ruby download.rb -u username --drop-partition dev`. You can inspect available names with `--list-partitions`.

To quickly browse what you already downloaded, run `bundle exec ruby random.rb` and it opens 10 random files from `images/` by default. You can change the count with `-n`, for example `bundle exec ruby random.rb -n 25`. If you pass `-u username`, it only picks images from conversations indexed for that username, still limited to files in `images/`.

To inspect files already tracked in the ledger, run `bundle exec ruby info.rb [names ...]`. It matches each name fragment against stored paths and prints conversation/media metadata.

To compare the ledger with files on disk, run `bundle exec ruby info.rb --compare`. It reports files on disk that are not indexed and indexed paths that are missing on disk.

If you want to use multiple image folders, create `data/project_map.json` as a plain hash mapping conversation id to folders, or to `null` to skip downloads for that conversations.

A few practical notes: this depends on private internals, so expect breakage when they move things around. Keep cookie files local, never commit them and treat this as a practical personal utility, not by-the-book but it works.
