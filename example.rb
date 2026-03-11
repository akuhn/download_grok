require %(json)
require %(net/http)
require %(uri)
require %(openssl)
require %(pry)

require './cache'
require './extensions'


url = "https://x.com/i/api/graphql/9Hyh5D4-WXLnExZkONSkZg/GrokHistory?variables=%7B%7D"

http = Net::HTTP.new("x.com", 443)
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
http.use_ssl = true

def download(http, url)

  puts "Downloading #{url}"

  req = Net::HTTP::Get.new(URI url)

  req["authorization"] = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
  req["content-type"] = "application/json"
  req["x-csrf-token"] = "86f9839721a063ee07162f096d87ed5f19245ac0f697b3fe4c56bd09b891cc7e8ec445af379274c48adf6f92f26781df478b9fde6c0d72eadb2409b2890f2550f8bd7c21b61d044b0484318e2f41992b"
  req["user-agent"] = "Mozilla/5.0"
  req["x-twitter-active-user"] = "yes"
  req["x-twitter-auth-type"] = "OAuth2Session"
  req["x-twitter-client-language"] = "en-US"

  req["cookie"] = File.readlines('my_cookie.txt', chomp: true).join('; ')

  res = http.request(req)
  res.body
end

db = Cache.new 'my_cache.sqlite'

json = db.fetch(url) { download http, url }
history = (JSON.parse json).data.grok_conversation_history.items

history.each do |each|
  puts each.title
  p each.grokConversation.rest_id
end


