require %(json)
require %(net/http)
require %(uri)
require %(openssl)
require %(pry)

require_relative "cache"

class Client

  attr_reader :cache

  def initialize(cookie_fname, sqlite_fname, partition, flags)
    @cookie = File.readlines(cookie_fname, chomp: true).join('; ')
    @cache = Cache.new sqlite_fname, partition
    @flags = flags

    @http = Net::HTTP.new("x.com", 443)
    @http.use_ssl = true
  end

  def download_history(cursor = nil)
    self.download_graphql(
      "9Hyh5D4-WXLnExZkONSkZg/GrokHistory",
      { cursor: cursor }.compact,
    )
  end

  def each_conversation(no_incremental = false)
    raise unless block_given?
    cursor = nil

    loop do
      history = self.download_history(cursor)
      conversations = history.data.grok_conversation_history.items

      conversations.each do |each|
        title = each.title
        conversation_id = each.grokConversation.rest_id

        puts title
        puts "  #{conversation_id}"

        unless no_incremental
          conversation_url = self.build_conversation_url(conversation_id)
          previous_content = @cache.most_recent_content(conversation_url)
        end

        conversation = self.download_conversation(conversation_id)
        conversation['conversation_id'] = conversation_id.to_s

        unless no_incremental
          current_content = @cache.most_recent_content(conversation_url)
          if previous_content && previous_content == current_content
            puts "  unchanged since previous run, stopping incremental download"
            return
          end
        end

        yield conversation
      end

      break unless history.data.grok_conversation_history.include? 'cursor'
      cursor = history.data.grok_conversation_history.cursor
    end
  end

  def download_conversation(rest_id)
    self.download self.build_conversation_url(rest_id)
  end

  def build_conversation_url(rest_id)
    self.build_graphql_url(
      "pqR3-SwIRnMCt8pgdbPM8w/GrokConversationItemsByRestId",
      { restId: rest_id },
    )
  end

  def download_graphql(path, vars)
    self.download self.build_graphql_url(path, vars)
  end

  def build_graphql_url(path, vars)
    encoded = URI.encode_www_form_component(vars.to_json)
    "https://x.com/i/api/graphql/#{path}?variables=#{encoded}"
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
