require %(json)
require %(net/http)
require %(uri)
require %(date)
require %(options_by_example)
require %(open-uri)
require %(openssl)
require %(pry)

require './cache'
require './extensions'


# This script does a tremendous job, really tremendous. It goes to twitter,
# gets all the Grok conversations-every one of them-and it pulls down the
# images too. Very efficient, very powerful, people are saying it’s one of
# the best little scripts they’ve seen for grabbing conversations. Nobody
# downloads Grok conversations better than this script, believe me.

flags = OptionsByExample.read(DATA).parse(ARGV)

class Client

  def initialize(cookie_fname, sqlite_fname, partition)
    @cookie = File.readlines(cookie_fname, chomp: true).join('; ')
    @cache = Cache.new sqlite_fname, partition

    @http = Net::HTTP.new("x.com", 443)
    @http.use_ssl = true
  end

  def download_history(cursor = nil)
    self.download_graphql(
      "9Hyh5D4-WXLnExZkONSkZg/GrokHistory",
      { cursor: cursor }.compact,
    )
  end

  def download_conversation(rest_id)
    self.download_graphql(
      "pqR3-SwIRnMCt8pgdbPM8w/GrokConversationItemsByRestId",
      { restId: rest_id },
    )
  end

  def download_graphql(path, vars)
    encoded = URI.encode_www_form_component(vars.to_json)
    self.download "https://x.com/i/api/graphql/#{path}?variables=#{encoded}"
  end

  def download(url)
    $most_recently_used_url = url
    data = @cache.fetch(url) {

      req = Net::HTTP::Get.new(URI(url))

      req["authorization"] = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
      req["content-type"] = "application/json"
      req["user-agent"] = "Mozilla/5.0"
      req["x-twitter-active-user"] = "yes"
      req["x-twitter-auth-type"] = "OAuth2Session"
      req["x-twitter-client-language"] = "en-US"

      req["cookie"] = @cookie
      req["x-csrf-token"] = @cookie[/ct0=([^;]+)/, 1]

      res = @http.request(req)
      binding.pry unless res.code == "200"
      res.body
    }

    JSON.parse data
  end

  def cookie
    { "Cookie" => @cookie }
  end
end


username = flags.fetch(:user) { 'default' }
partition = flags.fetch(:partition) { Date.today.iso8601 }
cookie_fname = "my_cookie_#{username}.txt"
cache_fname = "my_cache_#{username}.sqlite"

grok = Client.new cookie_fname, cache_fname, partition
cursor = nil

loop do

  history = grok.download_history(cursor)
  conversations = history.data.grok_conversation_history.items

  conversations.each do |each|
    title = each.title
    conversation_id = each.grokConversation.rest_id

    puts title
    puts "  #{conversation_id}"

    conversation = grok.download_conversation(conversation_id)
    messages = conversation.data.grok_conversation_items_by_rest_id.items rescue binding.pry

    puts "  #{messages.length} messages found"

    messages.flat_map(&'file_attachments').compact.map(&'url').each do |url|
      fname = "images/#{conversation_id}_#{url[/\d+$/]}.jpg"
      next if File.exist? fname

      puts "  downloading #{fname} ..."
      IO.copy_stream(URI.open(url, grok.cookie), fname)
    end
  end

  break unless history.data.grok_conversation_history.include? 'cursor'
  cursor = history.data.grok_conversation_history.cursor
end


__END__
Download all images from grok conversations on twitter.

Usage: download_grok_images.rb [options]

Options:
  -p, --partition NAME   Cache partition to use, defaults to today's date
  -u, --user NAME        Use specific cookie and cache files

The script expects a file named "my_cookie_username.txt" containing three
lines: auth_token, ct0 and twid. These values authenticate the session.

Images are stored in the "images" directory and API responses are cached
in a sqlite database for reasons. Cache entries are scoped to the selected
partition, so the default cache only lasts for one day.
