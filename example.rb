require %(json)
require %(net/http)
require %(uri)
require %(open-uri)
require %(openssl)
require %(pry)

require './cache'
require './extensions'


$cookie = File.readlines('my_cookie.txt', chomp: true).join('; ')

http = Net::HTTP.new("x.com", 443)
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
http.use_ssl = true


def download(http, url)
  puts "Downloading #{url}"

  req = Net::HTTP::Get.new(URI(url))

  req["authorization"] = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
  req["content-type"] = "application/json"
  req["x-csrf-token"] = "418a47d5990039adec6b5944c1011c287f0de9540780e7071a2b4d8d0caf8d1c1ea43a1723d1d448d7087287657ab6660ad65f104321d419e5f50dfd10964643e41d22c2fef2a8874dcd65671e40f2f9"
  req["user-agent"] = "Mozilla/5.0"
  req["x-twitter-active-user"] = "yes"
  req["x-twitter-auth-type"] = "OAuth2Session"
  req["x-twitter-client-language"] = "en-US"

  req["cookie"] = $cookie

  res = http.request(req)
  binding.pry unless res.code == "200"
  res.body
end

def make_history_url()
  vars = URI.encode_www_form_component("{}")
  "https://x.com/i/api/graphql/9Hyh5D4-WXLnExZkONSkZg/GrokHistory?variables=#{vars}"
end

def make_conversation_url(rest_id)
  vars = URI.encode_www_form_component({restId: rest_id}.to_json)
  "https://x.com/i/api/graphql/pqR3-SwIRnMCt8pgdbPM8w/GrokConversationItemsByRestId?variables=#{vars}"
end

db = Cache.new 'my_cache.sqlite'

url = make_history_url
json = db.fetch(url) { download http, url }
history = (JSON.parse json).data.grok_conversation_history.items

history.each do |each|
  title = each.title
  rest_id = each.grokConversation.rest_id

  puts title
  puts "  #{rest_id}"

  url = make_conversation_url(rest_id)
  json = db.fetch(url) { download http, url }
  conversation = (JSON.parse json)

  messages = conversation.data.grok_conversation_items_by_rest_id.items

  puts "  #{messages.length} messages found"

  messages.flat_map(&'file_attachments').compact.map(&'url').each do |url|
    next if File.exist? fname = "images/img_#{url[/\d+$/]}.jpg"

    puts "    Downloading #{fname}..."
    IO.copy_stream(URI.open(url, "Cookie" => $cookie), fname)
  end
end


