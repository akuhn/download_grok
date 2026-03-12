# download_grok
 
This is a small Ruby script that logs into your Twitter session with your own cookies, walks your Grok conversation history, and downloads every attached image it can find.
 
The implementation is intentionally plain. It hits two GraphQL endpoints, uses sqlite as a dead-simple response cache, and keeps going page by page until history is exhausted. If something weird happens, it drops into pry because real debugging beats theory when an API response goes sideways.
 
You will need Ruby, bundler, and a cookie file named like `my_cookie_<username>.txt`. That file should contain your `auth_token`, `ct0`, and `twid` values (one per line). The script stitches them into a cookie header and sends requests as your authenticated session.
 
Run it like this:

```
bundle install
mkdir -p images
bundle exec ruby download_grok_images.rb [username]
```

If you omit `[username]`, it uses `default` and looks for `my_cookie_default.txt`. Responses are cached in `my_cache_<username>.sqlite`. Delete rows from that cache if you want to force a refetch for a specific URL, or delete the file if you want a full clean run.

A few practical notes. This depends on private X internals, so expect breakage when they move things around. Keep cookie files local, never commit them, and treat this as a practical personal utility: not by-the-book, but it works.
