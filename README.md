# download_grok

This is a small Ruby script that logs into your X session with your own cookies, walks your Grok conversation history, and downloads every attached image it can find. No framework, no ceremony, just `net/http`, a little sqlite cache, and a loop that keeps paging until there is nothing left.

It is intentionally direct. The script calls two GraphQL endpoints, keeps raw responses in sqlite so you do not hammer the API while iterating, and writes image files under `images/` with stable names based on conversation id and attachment id. If something weird happens, it drops into pry because debugging the real object in hand is usually faster than pretending edge cases do not exist.

You will need Ruby, bundler, and a cookie file named like `my_cookie_<username>.txt`. That file should contain your `auth_token`, `ct0`, and `twid` values (one per line). The script stitches them into a cookie header and sends requests as your authenticated session.

Run it like this:

`bundle install`

`mkdir -p images`

`bundle exec ruby download_grok_images.rb [username]`

If you omit `[username]`, it uses `default` and looks for `my_cookie_default.txt`. Responses are cached in `my_cache_<username>.sqlite`. Delete rows from that cache if you want to force a refetch for a specific URL, or delete the file if you want a full clean run.

A few practical notes. This depends on private, unofficial endpoints and a live logged-in cookie, so it can break whenever X changes internals. Treat this as a personal utility script, not a polished product. Keep your cookie files local and out of git. And yes, there are monkey patches here; they are small, they are useful, and they keep the traversal code readable.
