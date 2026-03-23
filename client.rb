require %(json)
require %(net/http)
require %(uri)
require %(openssl)
require %(pry)
require %(digest)

require './cache'

class Client

  attr_reader :cache
  attr_reader :hashed_user_id

  def initialize(cookie_fname, sqlite_fname, partition, flags)
    @cookie = File.readlines(cookie_fname, chomp: true).join('; ')
    @cache = Cache.new sqlite_fname, partition
    @flags = flags

    @http = Net::HTTP.new("x.com", 443)
    @http.use_ssl = true

    digest = Digest::SHA256.hexdigest(@cookie[/twid=u%3D(\d+)/])
    @hashed_user_id = (digest.to_i(16) % 100000000).to_s.rjust(8, '0')
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
      puts "  fetching #{url}" if @flags.include_verbose?

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
